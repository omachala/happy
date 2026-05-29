import * as React from 'react';
import { View, Text, Pressable, ScrollView } from 'react-native';
import { StyleSheet } from 'react-native-unistyles';
import { Modal } from '@/modal';
import { useClaudeUsage, type ClaudeUsage } from '@/hooks/useClaudeUsage';

// Color buckets for the 5-hour utilization pill. We don't bother with theme
// colors here — these are status indicators and need to read consistently
// across light/dark.
function pctColor(pct: number): string {
    if (pct >= 80) return '#FF3B30';
    if (pct >= 50) return '#FF9500';
    return '#34C759';
}

function fmtPct(pct: number): string {
    return `${Math.round(pct)}%`;
}

function fmtResetIn(isoResetsAt: string | null): string {
    if (!isoResetsAt) return '—';
    const ms = new Date(isoResetsAt).getTime() - Date.now();
    if (ms <= 0) return 'now';
    const mins = Math.floor(ms / 60_000);
    if (mins < 60) return `${mins}m`;
    const hrs = Math.floor(mins / 60);
    const remMin = mins % 60;
    if (hrs < 24) return remMin > 0 ? `${hrs}h ${remMin}m` : `${hrs}h`;
    const days = Math.floor(hrs / 24);
    return `${days}d ${hrs % 24}h`;
}

export const UsagePill = React.memo(function UsagePill() {
    const { usage, error } = useClaudeUsage();
    if (!usage && !error) return null;
    if (!usage) return null;

    const pct = usage.fiveHour.utilization;
    const color = pctColor(pct);

    const onPress = () => {
        Modal.show({
            component: UsageSheet,
            props: { usage },
        } as any);
    };

    return (
        <Pressable onPress={onPress} hitSlop={10} style={styles.pill}>
            <View style={[styles.dot, { backgroundColor: color }]} />
            <Text style={styles.pillText}>{fmtPct(pct)}</Text>
        </Pressable>
    );
});

interface UsageSheetProps {
    usage: ClaudeUsage;
    onClose?: () => void;
}

const UsageSheet = React.memo(function UsageSheet({ usage }: UsageSheetProps) {
    return (
        <View style={styles.sheet}>
            <View style={styles.header}>
                <Text style={styles.title}>Claude usage</Text>
                <Text style={styles.subtitle}>Anthropic account-wide</Text>
            </View>
            <ScrollView contentContainerStyle={styles.list}>
                <Section
                    label="Session (5h)"
                    pct={usage.fiveHour.utilization}
                    detail={`Resets in ${fmtResetIn(usage.fiveHour.resetsAt)}`}
                />
                <Section
                    label="Weekly (7d)"
                    pct={usage.sevenDay.utilization}
                    detail={`Resets in ${fmtResetIn(usage.sevenDay.resetsAt)}`}
                />
                {usage.extra && usage.extra.enabled && (
                    <Section
                        label="Extra (monthly)"
                        pct={usage.extra.utilization}
                        detail={`$${(usage.extra.usedCents / 100).toFixed(2)} / $${(usage.extra.limitCents / 100).toFixed(2)}`}
                    />
                )}
            </ScrollView>
        </View>
    );
});

function Section({ label, pct, detail }: { label: string; pct: number; detail: string }) {
    const color = pctColor(pct);
    const clamped = Math.min(Math.max(pct, 0), 100);
    return (
        <View style={styles.section}>
            <View style={styles.sectionHeader}>
                <Text style={styles.sectionLabel}>{label}</Text>
                <Text style={[styles.sectionPct, { color }]}>{fmtPct(pct)}</Text>
            </View>
            <View style={styles.barTrack}>
                <View style={[styles.barFill, { width: `${clamped}%`, backgroundColor: color }]} />
            </View>
            <Text style={styles.sectionDetail}>{detail}</Text>
        </View>
    );
}

const styles = StyleSheet.create((theme) => ({
    pill: {
        flexDirection: 'row',
        alignItems: 'center',
        paddingHorizontal: 10,
        paddingVertical: 5,
        borderRadius: 999,
        backgroundColor: theme.colors.surfaceHigh,
        marginRight: 6,
    },
    dot: {
        width: 6,
        height: 6,
        borderRadius: 3,
        marginRight: 6,
    },
    pillText: {
        fontSize: 12,
        fontVariant: ['tabular-nums'],
        color: theme.colors.text,
        fontWeight: '600' as const,
    },
    sheet: {
        backgroundColor: theme.colors.surface,
        borderRadius: 16,
        width: '100%',
        maxWidth: 480,
        overflow: 'hidden',
    },
    header: {
        paddingHorizontal: 20,
        paddingTop: 20,
        paddingBottom: 12,
        borderBottomWidth: StyleSheet.hairlineWidth,
        borderBottomColor: theme.colors.divider,
    },
    title: {
        fontSize: 17,
        fontWeight: '600' as const,
        color: theme.colors.text,
    },
    subtitle: {
        marginTop: 4,
        fontSize: 13,
        color: theme.colors.textSecondary,
    },
    list: {
        paddingHorizontal: 20,
        paddingVertical: 12,
    },
    section: {
        paddingVertical: 12,
    },
    sectionHeader: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'baseline',
        marginBottom: 8,
    },
    sectionLabel: {
        fontSize: 14,
        color: theme.colors.text,
        fontWeight: '500' as const,
    },
    sectionPct: {
        fontSize: 16,
        fontVariant: ['tabular-nums'],
        fontWeight: '600' as const,
    },
    barTrack: {
        height: 6,
        backgroundColor: theme.colors.divider,
        borderRadius: 3,
        overflow: 'hidden',
    },
    barFill: {
        height: 6,
        borderRadius: 3,
    },
    sectionDetail: {
        marginTop: 6,
        fontSize: 12,
        color: theme.colors.textSecondary,
    },
}));
