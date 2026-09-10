import React from 'react';
import { View, Pressable, Platform } from 'react-native';
import { Text } from '@/components/StyledText';
import { Machine } from '@/sync/storageTypes';
import { SessionRowData } from '@/sync/storage';
import { Ionicons } from '@expo/vector-icons';
import {
    type SessionState,
    formatPathRelativeToHome,
} from '@/utils/sessionUtils';
import { Typography } from '@/constants/Typography';
import { StatusDot } from './StatusDot';
import { useAllMachines } from '@/sync/storage';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import { t } from '@/text';
import { useNavigateToSession } from '@/hooks/useNavigateToSession';
import { SessionActionsAnchor, SessionActionsPopover } from './SessionActionsPopover';
import { useSessionActionAlert } from '@/hooks/useSessionQuickActions';
import { useNewSessionDraft } from '@/hooks/useNewSessionDraft';
import { useRouter } from 'expo-router';
import { ProviderIcon } from './ProviderIcon';
import { getRepoPath, getWorktreeName } from '@/utils/worktree';

// Status visualization for a session tile — pulsing-blue (thinking) >
// orange (permission) > green (waiting) > gray.
const STATUS_COLOR: Record<SessionState, { color: string; pulsing: boolean }> = {
    thinking: { color: '#007AFF', pulsing: true },
    permission_required: { color: '#FF9500', pulsing: true },
    waiting: { color: '#34C759', pulsing: false },
    disconnected: { color: '#999', pulsing: false },
};

interface ActiveSessionsGroupProps {
    sessions: SessionRowData[];
    selectedSessionId?: string;
}

type ProjectGroup = {
    projectPath: string;
    projectName: string; // last folder of displayPath, capitalized; "~" → "Home"
    sessions: SessionRowData[];
};

type MachineGroup = {
    machineId: string;
    machineName: string;
    projects: ProjectGroup[];
};

// Machine header — always shown, even with only one machine. Tapping the name
// jumps to the machine detail screen; tapping "+" opens a new session draft
// with this machine preselected.
const MachineHeader = React.memo(({ machineName, machineId }: {
    machineName: string;
    machineId: string;
}) => {
    const styles = stylesheet;
    const { theme } = useUnistyles();
    const router = useRouter();
    const draft = useNewSessionDraft();

    const onPress = React.useCallback(() => {
        if (machineId !== UNKNOWN_MACHINE_ID) {
            router.navigate(`/machine/${machineId}` as any);
        }
    }, [router, machineId]);

    const onAddPress = React.useCallback(() => {
        if (machineId !== UNKNOWN_MACHINE_ID) {
            draft.setMachineId(machineId);
        }
        router.navigate('/new');
    }, [router, machineId, draft]);

    return (
        <View style={styles.machineHeader}>
            <Pressable
                style={styles.machineHeaderMain}
                onPress={onPress}
                hitSlop={{ top: 4, bottom: 4 }}
            >
                <Ionicons
                    name="desktop-outline"
                    size={14}
                    color={theme.colors.text}
                    style={styles.machineHeaderIcon}
                />
                <Text style={styles.machineHeaderName} numberOfLines={1}>
                    {machineName}
                </Text>
            </Pressable>
            <Pressable
                onPress={onAddPress}
                hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}
                style={styles.machineHeaderAdd}
            >
                <Ionicons name="add" size={20} color={theme.colors.text} />
            </Pressable>
        </View>
    );
});

// One session = one tap target. The title repeats the folder name, so several
// sessions in the same folder read as siblings, told apart by the conversation
// name in the subtitle. A session running in a git worktree carries a branch
// badge next to the title.
// Long-press → session actions (archive, etc.).
const SessionTile = React.memo(({ session, projectName, selected, isLast }: {
    session: SessionRowData;
    projectName: string;
    selected: boolean;
    isLast: boolean;
}) => {
    const styles = stylesheet;
    const { theme } = useUnistyles();
    const navigateToSession = useNavigateToSession();
    const [actionsAnchor, setActionsAnchor] = React.useState<SessionActionsAnchor | null>(null);

    const worktreeName = React.useMemo(
        () => (session.path ? getWorktreeName(session.path) : null),
        [session.path],
    );

    const statusColor = session.hasUnread
        ? { color: '#007AFF', pulsing: false }
        : STATUS_COLOR[session.state];

    const handlePress = React.useCallback(() => {
        navigateToSession(session.id);
    }, [navigateToSession, session.id]);

    const handleContextMenu = React.useCallback((event: any) => {
        event.preventDefault?.();
        event.stopPropagation?.();
        setActionsAnchor({
            type: 'point',
            x: event.nativeEvent.clientX ?? event.nativeEvent.pageX ?? 0,
            y: event.nativeEvent.clientY ?? event.nativeEvent.pageY ?? 0,
        });
    }, []);

    const showActionAlert = useSessionActionAlert(session.id);
    const menuProps = Platform.OS === 'web'
        ? ({ onContextMenu: handleContextMenu } as any)
        : { onLongPress: showActionAlert };

    return (
        <View style={styles.tileWrapper}>
            <Pressable
                style={[
                    styles.tile,
                    selected && styles.tileSelected,
                    isLast && styles.tileLast,
                ]}
                onPress={handlePress}
                {...menuProps}
            >
                <View style={styles.tileTextColumn}>
                    <View style={styles.tileTitleRow}>
                        <Text style={[styles.tileTitle, session.hasUnread && styles.tileTitleUnread]} numberOfLines={1}>
                            {projectName}
                        </Text>
                        {worktreeName && (
                            <View style={styles.worktreeBadge}>
                                <Ionicons
                                    name="git-branch-outline"
                                    size={11}
                                    color={theme.colors.textSecondary}
                                />
                                <Text style={styles.worktreeBadgeText} numberOfLines={1}>
                                    {worktreeName}
                                </Text>
                            </View>
                        )}
                    </View>
                    {session.name ? (
                        <Text style={[styles.tileSubtitle, session.hasUnread && styles.tileSubtitleUnread]} numberOfLines={1}>
                            {session.name}
                        </Text>
                    ) : null}
                    {session.identityLine && (
                        <View style={styles.sessionIdentityRow}>
                            <ProviderIcon kind={session.providerKind} size={11} />
                            <Text style={styles.sessionIdentity} numberOfLines={1}>
                                {session.identityLine}{session.modelName ? ` · ${session.modelName}` : ''}{session.activitySummary ? ` · ${session.activitySummary}` : ''}
                            </Text>
                        </View>
                    )}
                </View>
                <View style={styles.tileDot}>
                    <StatusDot color={statusColor.color} isPulsing={statusColor.pulsing} />
                </View>
            </Pressable>

            {Platform.OS === 'web' && (
                <SessionActionsPopover
                    anchor={actionsAnchor}
                    onClose={() => setActionsAnchor(null)}
                    sessionId={session.id}
                    visible={!!actionsAnchor}
                />
            )}
        </View>
    );
});

const UNKNOWN_MACHINE_ID = '__unknown__';

export function ActiveSessionsGroupCompact({ sessions, selectedSessionId }: ActiveSessionsGroupProps) {
    const styles = stylesheet;
    const machines = useAllMachines();

    const machinesMap = React.useMemo(() => {
        const map: Record<string, Machine> = {};
        machines.forEach(m => { map[m.id] = m; });
        return map;
    }, [machines]);

    const machineGroups: MachineGroup[] = React.useMemo(() => {
        const unknownText = t('status.unknown');
        const byMachine = new Map<string, MachineGroup>();

        sessions.forEach(session => {
            const machineId = session.machineId || UNKNOWN_MACHINE_ID;
            const machine = machineId !== UNKNOWN_MACHINE_ID ? machinesMap[machineId] : null;
            const machineName = machine?.metadata?.displayName
                || machine?.metadata?.host
                || (machineId !== UNKNOWN_MACHINE_ID ? machineId : `<${unknownText}>`);

            let mg = byMachine.get(machineId);
            if (!mg) {
                mg = { machineId, machineName, projects: [] };
                byMachine.set(machineId, mg);
            }

            // A session running in a git worktree lives at
            // <repo>/.dev/worktree/<name> — group it under <repo> so it stays
            // with its project instead of appearing as an unrelated tile.
            const projectPath = getRepoPath(session.path || '');
            let pg = mg.projects.find(p => p.projectPath === projectPath);
            if (!pg) {
                const displayPath = formatPathRelativeToHome(projectPath, session.homeDir ?? undefined);
                const segments = displayPath.split(/[/\\]/).filter(Boolean);
                const rawName = segments.length > 0 ? segments[segments.length - 1] : displayPath;
                // "~" means the session is rooted at $HOME — show that as "Home".
                const projectName = rawName === '~'
                    ? t('common.home')
                    : rawName.charAt(0).toUpperCase() + rawName.slice(1);
                pg = { projectPath, projectName, sessions: [] };
                mg.projects.push(pg);
            }
            pg.sessions.push(session);
        });

        // Sort: machines alphabetically; within each machine, by most-recent activity.
        const result = Array.from(byMachine.values()).sort((a, b) => a.machineName.localeCompare(b.machineName));
        result.forEach(mg => {
            mg.projects.forEach(p => p.sessions.sort((a, b) => (b.createdAt ?? 0) - (a.createdAt ?? 0)));
            mg.projects.sort((a, b) => {
                const aMax = Math.max(...a.sessions.map(s => s.createdAt ?? 0));
                const bMax = Math.max(...b.sessions.map(s => s.createdAt ?? 0));
                return bMax - aMax;
            });
        });
        return result;
    }, [sessions, machinesMap]);

    return (
        <View style={styles.container}>
            {machineGroups.map(mg => (
                <View key={mg.machineId} style={styles.machineSection}>
                    <MachineHeader
                        machineName={mg.machineName}
                        machineId={mg.machineId}
                    />
                    <View style={styles.tileGroup}>
                        {mg.projects.flatMap(pg =>
                            pg.sessions.map(s => ({ session: s, projectName: pg.projectName })),
                        ).map((entry, idx, all) => (
                            <SessionTile
                                key={entry.session.id}
                                session={entry.session}
                                projectName={entry.projectName}
                                selected={entry.session.id === selectedSessionId}
                                isLast={idx === all.length - 1}
                            />
                        ))}
                    </View>
                </View>
            ))}
        </View>
    );
}

const stylesheet = StyleSheet.create((theme) => ({
    container: {
        backgroundColor: theme.colors.groupped.background,
        paddingTop: 4,
    },
    machineSection: {
        marginTop: 16,
    },
    machineHeader: {
        flexDirection: 'row',
        alignItems: 'center',
        paddingHorizontal: Platform.select({ ios: 24, default: 20 }),
        paddingVertical: 8,
    },
    machineHeaderMain: {
        flex: 1,
        flexDirection: 'row',
        alignItems: 'center',
    },
    machineHeaderIcon: {
        marginRight: 7,
    },
    machineHeaderName: {
        fontSize: 17,
        color: theme.colors.text,
        ...Typography.default('semiBold'),
        letterSpacing: -0.2,
        flexShrink: 1,
    },
    machineHeaderAdd: {
        padding: 4,
        marginLeft: 4,
    },
    tileGroup: {
        marginHorizontal: Platform.select({ ios: 16, default: 12 }),
        backgroundColor: theme.colors.surface,
        borderRadius: Platform.select({ ios: 12, default: 16 }),
        overflow: 'hidden',
        shadowColor: theme.colors.shadow.color,
        shadowOffset: { width: 0, height: 0.33 },
        shadowOpacity: theme.colors.shadow.opacity,
        shadowRadius: 0,
        elevation: 1,
    },
    tileWrapper: {
        backgroundColor: theme.colors.surface,
    },
    tile: {
        minHeight: 60,
        flexDirection: 'row',
        alignItems: 'center',
        paddingHorizontal: 20,
        paddingVertical: 16,
        borderBottomWidth: StyleSheet.hairlineWidth,
        borderBottomColor: theme.colors.divider,
    },
    tileLast: {
        borderBottomWidth: 0,
    },
    tileSelected: {
        backgroundColor: theme.colors.surfaceSelected,
    },
    tileTextColumn: {
        flex: 1,
        flexShrink: 1,
        minWidth: 0,
    },
    tileTitleRow: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 8,
    },
    worktreeBadge: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 3,
        flexShrink: 1,
        minWidth: 0,
        paddingHorizontal: 6,
        paddingVertical: 1,
        borderRadius: 6,
        backgroundColor: theme.colors.groupped.background,
    },
    worktreeBadgeText: {
        fontSize: 11,
        color: theme.colors.textSecondary,
        ...Typography.default('regular'),
        flexShrink: 1,
    },
    tileTitle: {
        fontSize: 17,
        color: theme.colors.text,
        ...Typography.default('regular'),
        letterSpacing: -0.1,
        flexShrink: 1,
        minWidth: 0,
    },
    tileTitleUnread: {
        ...Typography.default('semiBold'),
    },
    tileSubtitle: {
        fontSize: 12,
        color: theme.colors.textSecondary,
        marginTop: 2,
        ...Typography.default('regular'),
    },
    tileSubtitleUnread: {
        color: theme.colors.text,
        ...Typography.default('semiBold'),
    },
    sessionIdentity: {
        fontSize: 11,
        color: theme.colors.textSecondary,
        ...Typography.default('regular'),
        flexShrink: 1,
    },
    sessionIdentityRow: {
        marginTop: 2,
        flexDirection: 'row',
        alignItems: 'center',
        gap: 4,
    },
    tileDot: {
        marginLeft: 10,
    },
}));
