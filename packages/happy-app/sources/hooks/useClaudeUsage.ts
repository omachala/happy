import * as React from 'react';
import { useAuth } from '@/auth/AuthContext';
import { getServerUrl } from '@/sync/serverConfig';

// Polls happy-server's /v1/account/anthropic/usage endpoint, which forwards
// to Anthropic's OAuth usage API using the user's CLI-registered token
// (server-side refresh handled). No token paste needed in-app — relies on
// `happy connect claude` having been run on at least one machine.

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
    const auth = useAuth();
    const token = auth.credentials?.token ?? null;
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
                const res = await fetch(`${getServerUrl()}/v1/account/anthropic/usage`, {
                    headers: { 'Authorization': `Bearer ${token}` },
                });
                if (cancelled) return;
                if (res.status === 404) {
                    // Account not connected on the server — silently no-op.
                    setUsage(null);
                    setError(null);
                    return;
                }
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
