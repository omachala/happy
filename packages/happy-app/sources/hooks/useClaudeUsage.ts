import * as React from 'react';
import { useAuth } from '@/auth/AuthContext';
import { kvGet } from '@/sync/apiKv';

// Reads the Anthropic usage snapshot that the happy-cli daemon publishes
// into KV under `anthropic_usage`. The CLI runs on the user's Mac, reads the
// Claude Code OAuth token from macOS Keychain, hits Anthropic's usage API,
// and writes the result into KV every ~60s. No server changes required —
// happy-server treats KV values as opaque strings.
//
// If no daemon is running anywhere on the account, KV stays empty and the
// hook returns null usage (pill hides). Once the daemon ticks once, the pill
// appears within the next app poll (60s).

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
const KV_KEY = 'anthropic_usage';

export function useClaudeUsage(): {
    usage: ClaudeUsage | null;
    error: string | null;
    refresh: () => void;
} {
    const auth = useAuth();
    const credentials = auth.credentials;
    const [usage, setUsage] = React.useState<ClaudeUsage | null>(null);
    const [error, setError] = React.useState<string | null>(null);
    const [tick, setTick] = React.useState(0);

    React.useEffect(() => {
        if (!credentials) {
            setUsage(null);
            setError(null);
            return;
        }
        let cancelled = false;
        (async () => {
            try {
                const item = await kvGet(credentials, KV_KEY);
                if (cancelled) return;
                if (!item) {
                    // No daemon has written yet — silently hide.
                    setUsage(null);
                    setError(null);
                    return;
                }
                const data: any = JSON.parse(item.value);
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
                setError(e?.message ?? 'kv read failed');
            }
        })();
        return () => { cancelled = true; };
    }, [credentials, tick]);

    React.useEffect(() => {
        if (!credentials) return;
        const id = setInterval(() => setTick(t => t + 1), REFRESH_MS);
        return () => clearInterval(id);
    }, [credentials]);

    const refresh = React.useCallback(() => setTick(t => t + 1), []);
    return { usage, error, refresh };
}
