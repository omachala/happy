import { readFile } from "node:fs/promises";
import { type FastifyReply } from "fastify";
import { type Fastify } from "../types";
import { decryptString, encryptString } from "@/modules/encrypt";
import { db } from "@/storage/db";
import { log } from "@/utils/log";

// Forwards the Claude Code OAuth-account usage stats to the calling client.
// The Anthropic access token is stored encrypted in ServiceAccountToken
// (vendor='anthropic') after `happy connect claude`. The token's the same one
// `claude` reads from the macOS Keychain — short-lived (~1h), refreshed here
// when stale using the bundled refresh_token.
//
// Responses are cached briefly per-user: every connected client (phone, web,
// desktop) polls this on its own 60s timer, and Anthropic's usage endpoint
// rate-limits (429) if hit too often — a previous LAN-only proxy crashed
// outright on that. A short cache keeps N clients to ~1 upstream call.
//
// The token endpoint rate-limits per IP too, and Din's own `claude` sessions
// refresh through it. A failed refresh used to be retried on every 60s poll,
// which kept the IP rate-limited indefinitely once the token had expired
// (2026-10-11: pill stuck on "Server error 429"). Failed refreshes now back
// off, and the last good snapshot is served for a while when upstream fails.
//
// The stored token is copied from a machine's `claude login`, so it shares a
// single-use refresh token with that machine's Claude Code. Whichever side
// refreshes first invalidates the other ("Refresh token not found or
// invalid"). When ANTHROPIC_CREDENTIALS_FILE points at a host's live
// ~/.claude/.credentials.json, its access token is used as-is and never
// refreshed here; Claude Code on that host keeps it fresh. It only serves the
// account named in ANTHROPIC_CREDENTIALS_ACCOUNT, since it's one person's login.

const TOKEN_URL = 'https://platform.claude.com/v1/oauth/token';
const USAGE_URL = 'https://api.anthropic.com/api/oauth/usage';
// Anthropic OAuth client id used by the Claude Code CLI; reused for refresh.
const OAUTH_CLIENT_ID = '9d1c250a-e61b-44d9-88ed-5944d1962f5e';

const REFRESH_WINDOW_MS = 60_000;
const CACHE_TTL_MS = 30_000;
// After an upstream 429 without Retry-After, don't call again for this long.
const RATE_LIMITED_TTL_MS = 5 * 60_000;
const REFRESH_BACKOFF_MIN_MS = 5 * 60_000;
const REFRESH_BACKOFF_MAX_MS = 60 * 60_000;
// How long a last-good snapshot may stand in for a failing upstream.
const STALE_MAX_AGE_MS = 2 * 60 * 60_000;

type StoredAnthropicToken = {
    oauth: {
        raw: any;
        token: string;
        expires: number;
    };
};

type CachedUsage = {
    expiresAt: number;
    status: number;
    contentType: string;
    body: string;
};

const CREDENTIALS_FILE = process.env.ANTHROPIC_CREDENTIALS_FILE;
const CREDENTIALS_ACCOUNT = process.env.ANTHROPIC_CREDENTIALS_ACCOUNT;

const usageCache = new Map<string, CachedUsage>();
const lastGood = new Map<string, { at: number; contentType: string; body: string }>();
const refreshBackoff = new Map<string, { until: number; delayMs: number }>();

export function anthropicUsageRoutes(app: Fastify) {

    app.get('/v1/account/anthropic/usage', {
        preHandler: app.authenticate,
    }, async (request, reply) => {
        const userId = request.userId;

        const cached = usageCache.get(userId);
        if (cached && cached.expiresAt > Date.now()) {
            reply.code(cached.status).header('content-type', cached.contentType).send(cached.body);
            return;
        }

        const hostToken = userId === CREDENTIALS_ACCOUNT ? await readHostAccessToken() : null;
        if (hostToken) {
            return fetchUsage(userId, hostToken, reply);
        }

        const row = await db.serviceAccountToken.findUnique({
            where: { accountId_vendor: { accountId: userId, vendor: 'anthropic' } },
            select: { token: true },
        });
        if (!row) {
            return reply.code(404).send({ error: 'Anthropic account not connected. Run `happy connect claude` on a machine.' });
        }

        const encryptionKey: string[] = ['user', userId, 'vendors', 'anthropic', 'token'];
        let stored: StoredAnthropicToken;
        try {
            const raw = decryptString(encryptionKey, row.token);
            stored = JSON.parse(raw);
        } catch (err) {
            log({ module: 'anthropic-usage', level: 'error' }, `Failed to decrypt/parse stored token for ${userId}: ${(err as Error).message}`);
            return reply.code(500).send({ error: 'Stored token is unreadable.' });
        }

        let accessToken = stored.oauth?.token;
        const expiresAt = stored.oauth?.expires ?? 0;
        const refreshToken = stored.oauth?.raw?.refresh_token as string | undefined;

        if (!accessToken) {
            return reply.code(401).send({ error: 'No access token on record.' });
        }

        // Refresh proactively when within the refresh window. If refresh fails
        // we still try the existing token — Anthropic will reject it cleanly.
        const backoff = refreshBackoff.get(userId);
        if (Date.now() >= expiresAt - REFRESH_WINDOW_MS && refreshToken && !(backoff && backoff.until > Date.now())) {
            try {
                const refreshed = await refreshAnthropicToken(refreshToken);
                if (refreshed) {
                    accessToken = refreshed.access_token;
                    const updated: StoredAnthropicToken = {
                        oauth: {
                            raw: { ...stored.oauth.raw, ...refreshed },
                            token: refreshed.access_token,
                            expires: Date.now() + refreshed.expires_in * 1000,
                        },
                    };
                    const reencrypted = encryptString(encryptionKey, JSON.stringify(updated));
                    await db.serviceAccountToken.update({
                        where: { accountId_vendor: { accountId: userId, vendor: 'anthropic' } },
                        data: { token: reencrypted, updatedAt: new Date() },
                    });
                }
                refreshBackoff.delete(userId);
            } catch (err) {
                const delayMs = backoff ? Math.min(backoff.delayMs * 2, REFRESH_BACKOFF_MAX_MS) : REFRESH_BACKOFF_MIN_MS;
                refreshBackoff.set(userId, { until: Date.now() + delayMs, delayMs });
                log({ module: 'anthropic-usage', level: 'warn' }, `Refresh failed for ${userId}, next try in ${delayMs / 60_000}min: ${(err as Error).message}`);
            }
        }

        return fetchUsage(userId, accessToken, reply);
    });
}

async function readHostAccessToken(): Promise<string | null> {
    if (!CREDENTIALS_FILE) return null;
    try {
        const oauth = JSON.parse(await readFile(CREDENTIALS_FILE, 'utf8')).claudeAiOauth;
        if (oauth?.accessToken && (!oauth.expiresAt || oauth.expiresAt > Date.now())) {
            return oauth.accessToken;
        }
        log({ module: 'anthropic-usage', level: 'warn' }, `Host credentials in ${CREDENTIALS_FILE} are expired, falling back to stored token`);
    } catch (err) {
        log({ module: 'anthropic-usage', level: 'warn' }, `Cannot read ${CREDENTIALS_FILE}: ${(err as Error).message}`);
    }
    return null;
}

async function fetchUsage(userId: string, accessToken: string, reply: FastifyReply) {
    try {
        const res = await fetch(USAGE_URL, {
            headers: {
                'Authorization': `Bearer ${accessToken}`,
                'anthropic-beta': 'oauth-2025-04-20',
                'User-Agent': 'claude-code/2.0.32',
            },
        });
        const body = await res.text();
        const contentType = res.headers.get('content-type') ?? 'application/json';
        if (res.ok) {
            lastGood.set(userId, { at: Date.now(), contentType, body });
            usageCache.set(userId, { expiresAt: Date.now() + CACHE_TTL_MS, status: res.status, contentType, body });
            return reply.code(res.status).header('content-type', contentType).send(body);
        }

        log({ module: 'anthropic-usage', level: 'warn' }, `Upstream usage ${res.status} for ${userId}: ${body.slice(0, 200)}`);
        let ttl = CACHE_TTL_MS;
        if (res.status === 429) {
            const retryAfter = Number(res.headers.get('retry-after'));
            ttl = retryAfter > 0 ? retryAfter * 1000 : RATE_LIMITED_TTL_MS;
        }
        const good = lastGood.get(userId);
        const served = good && Date.now() - good.at < STALE_MAX_AGE_MS
            ? { status: 200, contentType: good.contentType, body: good.body }
            : { status: res.status, contentType, body };
        usageCache.set(userId, { expiresAt: Date.now() + ttl, ...served });
        reply.code(served.status).header('content-type', served.contentType).send(served.body);
    } catch (err) {
        log({ module: 'anthropic-usage', level: 'error' }, `Upstream fetch failed: ${(err as Error).message}`);
        return reply.code(502).send({ error: 'Upstream Anthropic call failed.' });
    }
}

async function refreshAnthropicToken(refreshToken: string): Promise<{ access_token: string; refresh_token: string; expires_in: number } | null> {
    const res = await fetch(TOKEN_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            grant_type: 'refresh_token',
            refresh_token: refreshToken,
            client_id: OAUTH_CLIENT_ID,
        }),
    });
    if (!res.ok) {
        throw new Error(`token endpoint ${res.status}: ${(await res.text()).slice(0, 200)}`);
    }
    const data = await res.json() as any;
    if (!data?.access_token || typeof data.expires_in !== 'number') return null;
    return {
        access_token: data.access_token,
        refresh_token: data.refresh_token ?? refreshToken,
        expires_in: data.expires_in,
    };
}
