import * as React from 'react';
import { useLocalSetting } from '@/sync/storage';

// Polls Anthropic's /api/oauth/usage endpoint using the user's Claude Code
// OAuth access token (pasted once into Settings). The token is the same one
// `claude` reads from the macOS Keychain entry "Claude Code-credentials" —
// see the omachala/claude-usage gist for the CLI version of this call.
// On token absence or fetch failure we return null and let the UI hide.

export type ClaudeUsage = {
    fiveHour: { utilization: number; resetsAt: string | null };
    sevenDay: { utilization: number; resetsAt: string | null };
    extra: {
        enabled: boolean;
        utilization: number;
        usedCents: number;
        limitCents: number;
    } | null;
};

const ENDPOINT = 'https://api.anthropic.com/api/oauth/usage';
const REFRESH_MS = 60_000;

export function useClaudeUsage(): {
    usage: ClaudeUsage | null;
    error: string | null;
    refresh: () => void;
} {
    const token = useLocalSetting('anthropicOauthAccessToken');
    const [usage, setUsage] = React.useState<ClaudeUsage | null>(null);
    const [error, setError] = React.useState<string | null>(null);
    const [tick, setTick] = React.useState(0);

    React.useEffect(() => {
        if (!token) {
            setUsage(null);
            setError(null);
            return;
        }
        let cancelled = false;
        (async () => {
            try {
                const res = await fetch(ENDPOINT, {
                    headers: {
                        'Authorization': `Bearer ${token}`,
                        'anthropic-beta': 'oauth-2025-04-20',
                        'User-Agent': 'claude-code/2.0.32',
                    },
                });
                if (cancelled) return;
                if (!res.ok) {
                    setError(`HTTP ${res.status}`);
                    return;
                }
                const data: any = await res.json();
                setError(null);
                setUsage({
                    fiveHour: {
                        utilization: Number(data?.five_hour?.utilization ?? 0),
                        resetsAt: data?.five_hour?.resets_at ?? null,
                    },
                    sevenDay: {
                        utilization: Number(data?.seven_day?.utilization ?? 0),
                        resetsAt: data?.seven_day?.resets_at ?? null,
                    },
                    extra: data?.extra_usage
                        ? {
                            enabled: Boolean(data.extra_usage.is_enabled),
                            utilization: Number(data.extra_usage.utilization ?? 0),
                            usedCents: Number(data.extra_usage.used_credits ?? 0),
                            limitCents: Number(data.extra_usage.monthly_limit ?? 0),
                        }
                        : null,
                });
            } catch (e: any) {
                if (cancelled) return;
                setError(e?.message ?? 'fetch failed');
            }
        })();
        return () => { cancelled = true; };
    }, [token, tick]);

    React.useEffect(() => {
        if (!token) return;
        const id = setInterval(() => setTick(t => t + 1), REFRESH_MS);
        return () => clearInterval(id);
    }, [token]);

    const refresh = React.useCallback(() => setTick(t => t + 1), []);
    return { usage, error, refresh };
}
