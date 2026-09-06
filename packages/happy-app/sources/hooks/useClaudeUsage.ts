import * as React from 'react';
import { getCurrentAuth } from '@/auth/AuthContext';
import { getServerUrl } from '@/sync/serverConfig';
import { getHappyClientId } from '@/sync/apiSocket';

// Fetches the Anthropic 5h/7d usage snapshot from happy-server, which itself
// proxies api.anthropic.com/api/oauth/usage using the Claude Code OAuth token
// registered via `happy connect claude`. Polls every 60s. The pill always
// renders — on any failure it shows an explicit error state rather than
// disappearing, so a broken/unreachable/unconnected state is visible instead
// of silently invisible.

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

const REFRESH_MS = 60_000;

export function useClaudeUsage(): {
    usage: ClaudeUsage | null;
    error: string | null;
    refresh: () => void;
} {
    const [usage, setUsage] = React.useState<ClaudeUsage | null>(null);
    const [error, setError] = React.useState<string | null>(null);
    const [tick, setTick] = React.useState(0);

    React.useEffect(() => {
        let cancelled = false;
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 5000);
        (async () => {
            const credentials = getCurrentAuth()?.credentials;
            if (!credentials) {
                if (cancelled) return;
                setUsage(null);
                setError('Not logged in');
                return;
            }
            try {
                const res = await fetch(`${getServerUrl()}/v1/account/anthropic/usage`, {
                    signal: controller.signal,
                    headers: {
                        'Authorization': `Bearer ${credentials.token}`,
                        'X-Happy-Client': getHappyClientId(),
                    },
                });
                if (cancelled) return;
                if (!res.ok) {
                    setUsage(null);
                    setError(res.status === 404 ? 'Anthropic account not connected' : `Server error ${res.status}`);
                    return;
                }
                const data: any = await res.json();
                if (cancelled) return;
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
                    extra: data?.extra_usage?.is_enabled
                        ? {
                            enabled: true,
                            utilization: Number(data.extra_usage.utilization ?? 0),
                            usedCents: Number(data.extra_usage.used_credits ?? 0),
                            limitCents: Number(data.extra_usage.monthly_limit ?? 0),
                        }
                        : null,
                });
            } catch (e) {
                if (cancelled) return;
                setUsage(null);
                setError(e instanceof Error && e.name === 'AbortError' ? 'Timed out' : 'Unreachable');
            } finally {
                clearTimeout(timeout);
            }
        })();
        return () => { cancelled = true; controller.abort(); clearTimeout(timeout); };
    }, [tick]);

    React.useEffect(() => {
        const id = setInterval(() => setTick(t => t + 1), REFRESH_MS);
        return () => clearInterval(id);
    }, []);

    const refresh = React.useCallback(() => setTick(t => t + 1), []);
    return { usage, error, refresh };
}
