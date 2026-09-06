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

const TOKEN_URL = 'https://console.anthropic.com/v1/oauth/token';
const USAGE_URL = 'https://api.anthropic.com/api/oauth/usage';
// Anthropic OAuth client id used by the Claude Code CLI; reused for refresh.
const OAUTH_CLIENT_ID = '9d1c250a-e61b-44d9-88ed-5944d1962f5e';

const REFRESH_WINDOW_MS = 60_000;
const CACHE_TTL_MS = 30_000;

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

const usageCache = new Map<string, CachedUsage>();

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
        if (Date.now() >= expiresAt - REFRESH_WINDOW_MS && refreshToken) {
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
            } catch (err) {
                log({ module: 'anthropic-usage', level: 'warn' }, `Refresh failed for ${userId}: ${(err as Error).message}`);
            }
        }

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
            usageCache.set(userId, { expiresAt: Date.now() + CACHE_TTL_MS, status: res.status, contentType, body });
            reply.code(res.status).header('content-type', contentType).send(body);
        } catch (err) {
            log({ module: 'anthropic-usage', level: 'error' }, `Upstream fetch failed: ${(err as Error).message}`);
            return reply.code(502).send({ error: 'Upstream Anthropic call failed.' });
        }
    });
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
    if (!res.ok) return null;
    const data = await res.json() as any;
    if (!data?.access_token || typeof data.expires_in !== 'number') return null;
    return {
        access_token: data.access_token,
        refresh_token: data.refresh_token ?? refreshToken,
        expires_in: data.expires_in,
    };
}
