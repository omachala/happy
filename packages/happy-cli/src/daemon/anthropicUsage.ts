/**
 * Anthropic usage snapshot publisher (daemon-side).
 *
 * Periodically reads the Claude Code OAuth access token from macOS Keychain,
 * fetches the account-wide usage stats from api.anthropic.com, and publishes
 * the result into the user's KV store under `anthropic_usage`. The mobile
 * app polls that key to render the home-header usage pill.
 *
 * Token refresh is the responsibility of `claude` itself — the local Claude
 * Code CLI keeps the Keychain entry up to date whenever the user invokes it.
 * If the read token is expired (Anthropic returns 401) we just skip this
 * tick and try again on the next heartbeat.
 *
 * Cross-platform: macOS reads from Keychain (`Claude Code-credentials`),
 * Linux reads from `~/.claude/.credentials.json`. Missing/unreadable
 * credentials simply skip the tick.
 */

import { execFile } from 'child_process';
import { promisify } from 'util';
import { promises as fs } from 'fs';
import { homedir } from 'os';
import { join } from 'path';
import axios from 'axios';

import { configuration } from '@/configuration';
import { logger } from '@/ui/logger';

const execFileAsync = promisify(execFile);

const KEYCHAIN_SERVICE = 'Claude Code-credentials';
const LINUX_CREDENTIALS_PATH = join(homedir(), '.claude', '.credentials.json');
const USAGE_URL = 'https://api.anthropic.com/api/oauth/usage';
const KV_KEY = 'anthropic_usage';
const CLAUDE_CODE_UA = 'claude-code/2.0.32';

type AnthropicUsagePayload = {
    five_hour?: { utilization?: number; resets_at?: string | null };
    seven_day?: { utilization?: number; resets_at?: string | null };
    extra_usage?: {
        is_enabled?: boolean;
        utilization?: number;
        used_credits?: number;
        monthly_limit?: number;
    } | null;
};

// Module-level state: kept across heartbeat ticks so we can satisfy the KV
// store's optimistic-concurrency check. Reset on 409 to whatever the server
// reports as current.
let lastKvVersion: number | null = null;

async function readClaudeCodeAccessToken(): Promise<string | null> {
    try {
        const raw = process.platform === 'darwin'
            ? (await execFileAsync(
                '/usr/bin/security',
                ['find-generic-password', '-s', KEYCHAIN_SERVICE, '-w'],
                { timeout: 5000 },
            )).stdout.trim()
            : (await fs.readFile(LINUX_CREDENTIALS_PATH, 'utf8')).trim();
        if (!raw) return null;
        const parsed = JSON.parse(raw);
        const token = parsed?.claudeAiOauth?.accessToken;
        return typeof token === 'string' && token.length > 0 ? token : null;
    } catch {
        // Credential entry missing, locked, or unparseable — caller skips this tick.
        return null;
    }
}

async function fetchUsage(accessToken: string): Promise<AnthropicUsagePayload | null> {
    try {
        const response = await axios.get<AnthropicUsagePayload>(USAGE_URL, {
            headers: {
                'Authorization': `Bearer ${accessToken}`,
                'anthropic-beta': 'oauth-2025-04-20',
                'User-Agent': CLAUDE_CODE_UA,
            },
            timeout: 8000,
            validateStatus: () => true,
        });
        if (response.status !== 200) {
            logger.debug(`[anthropic-usage] Skipping tick: HTTP ${response.status}`);
            return null;
        }
        return response.data;
    } catch (err) {
        logger.debug(`[anthropic-usage] fetch failed: ${(err as Error).message}`);
        return null;
    }
}

async function postUsageMutation(
    authToken: string,
    value: string,
    version: number,
): Promise<{ ok: true; version: number } | { conflict: true; version: number } | { ok: false }> {
    try {
        const response = await axios.post(
            `${configuration.serverUrl}/v1/kv`,
            { mutations: [{ key: KV_KEY, value, version }] },
            {
                headers: {
                    'Authorization': `Bearer ${authToken}`,
                    'Content-Type': 'application/json',
                    'X-Happy-Client': `cli-daemon/${configuration.currentCliVersion}`,
                },
                timeout: 8000,
                validateStatus: () => true,
            },
        );
        if (response.status === 200 && response.data?.success === true) {
            const versionFromServer = response.data?.results?.[0]?.version;
            return { ok: true, version: typeof versionFromServer === 'number' ? versionFromServer : version };
        }
        if (response.status === 409 && response.data?.success === false) {
            const reported = response.data?.errors?.[0]?.version;
            return { conflict: true, version: typeof reported === 'number' ? reported : -1 };
        }
        logger.debug(`[anthropic-usage] KV write HTTP ${response.status}`);
        return { ok: false };
    } catch (err) {
        logger.debug(`[anthropic-usage] KV write failed: ${(err as Error).message}`);
        return { ok: false };
    }
}

/**
 * One tick: read token, fetch usage, write to KV. Safe to call from the
 * daemon heartbeat — silently no-ops on any failure path (missing token,
 * Anthropic outage, server unreachable, etc.).
 */
export async function publishAnthropicUsageTick(authToken: string): Promise<void> {
    const accessToken = await readClaudeCodeAccessToken();
    if (!accessToken) return;

    const usage = await fetchUsage(accessToken);
    if (!usage) return;

    const payload = JSON.stringify({ ...usage, fetched_at: Date.now() });

    const version = lastKvVersion ?? -1;
    const first = await postUsageMutation(authToken, payload, version);
    if ('ok' in first && first.ok) {
        lastKvVersion = first.version;
        return;
    }
    if ('conflict' in first) {
        // Another writer (different machine?) raced us. Retry with their version.
        const retry = await postUsageMutation(authToken, payload, first.version);
        if ('ok' in retry && retry.ok) {
            lastKvVersion = retry.version;
        }
    }
}
