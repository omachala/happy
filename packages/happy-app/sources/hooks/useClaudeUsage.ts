import * as React from 'react';

// Fetches the Anthropic 5h/7d usage snapshot from the local home-network
// proxy at http://api.home/claude/usage. Endpoint runs on Din and returns
// the raw Anthropic schema verbatim. Polls every 60s. When unreachable
// (off the home LAN/VPN, or proxy down) the pill silently hides.

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
const ENDPOINT = 'http://api.home/claude/usage';

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
            try {
                const res = await fetch(ENDPOINT, { signal: controller.signal });
                if (cancelled) return;
                if (!res.ok) {
                    setUsage(null);
                    setError(null);
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
            } catch {
                if (cancelled) return;
                setUsage(null);
                setError(null);
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
