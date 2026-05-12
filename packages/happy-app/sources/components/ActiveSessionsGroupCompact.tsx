import React from 'react';
import { View, Pressable, Platform } from 'react-native';
import { Text } from '@/components/StyledText';
import { Machine } from '@/sync/storageTypes';
import { SessionRowData } from '@/sync/storage';
import { Ionicons, MaterialCommunityIcons } from '@expo/vector-icons';
import {
    type SessionState,
    formatPathRelativeToHome,
    vibingMessages,
} from '@/utils/sessionUtils';
import { Typography } from '@/constants/Typography';
import { StatusDot } from './StatusDot';
import { useAllMachines, useSessionGitStatus } from '@/sync/storage';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import { t } from '@/text';
import { useNavigateToSession } from '@/hooks/useNavigateToSession';
import { SessionActionsAnchor, SessionActionsPopover } from './SessionActionsPopover';
import { useSessionActionAlert } from '@/hooks/useSessionQuickActions';
import { isWorktreePath, getRepoPath, getWorktreeName } from '@/utils/worktree';
import { useNewSessionDraft } from '@/hooks/useNewSessionDraft';
import { useRouter } from 'expo-router';

// Status visualization for a project tile. We surface the most-active session's
// state — pulsing-blue (thinking) > orange (permission) > green (waiting) > gray.
const STATUS_PRIORITY: Record<SessionState, number> = {
    thinking: 4,
    permission_required: 3,
    waiting: 2,
    disconnected: 1,
};

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
    displayPath: string;
    projectName: string; // last folder of displayPath
    parentDir: string;   // displayPath without last folder
    sessions: SessionRowData[];
};

type MachineGroup = {
    machineId: string;
    machineName: string;
    projects: ProjectGroup[];
};

// Pick the session whose state is "most attention-worthy" — drives the tile's
// status dot. Ties broken by most-recent createdAt.
function pickLeadSession(sessions: SessionRowData[]): SessionRowData {
    let best = sessions[0];
    let bestScore = STATUS_PRIORITY[best.state] * 1e15 + (best.createdAt ?? 0);
    for (let i = 1; i < sessions.length; i++) {
        const s = sessions[i];
        const score = STATUS_PRIORITY[s.state] * 1e15 + (s.createdAt ?? 0);
        if (s.hasUnread) {
            // Unread sessions outrank everything except thinking
            const unreadScore = 5e15 + (s.createdAt ?? 0);
            if (unreadScore > bestScore) { best = s; bestScore = unreadScore; }
            continue;
        }
        if (score > bestScore) { best = s; bestScore = score; }
    }
    return best;
}

// Machine header — always shown, even with only one machine. Tapping jumps
// to the machine's detail screen.
const MachineHeader = React.memo(({ machineName, machineId, count }: {
    machineName: string;
    machineId: string;
    count: number;
}) => {
    const styles = stylesheet;
    const { theme } = useUnistyles();
    const router = useRouter();

    const onPress = React.useCallback(() => {
        if (machineId !== UNKNOWN_MACHINE_ID) {
            router.navigate(`/machine/${machineId}` as any);
        }
    }, [router, machineId]);

    return (
        <Pressable style={styles.machineHeader} onPress={onPress} hitSlop={{ top: 4, bottom: 4 }}>
            <Ionicons
                name="desktop-outline"
                size={14}
                color={theme.colors.text}
                style={styles.machineHeaderIcon}
            />
            <Text style={styles.machineHeaderName} numberOfLines={1}>
                {machineName}
            </Text>
            <Text style={styles.machineHeaderCount}>
                {count}
            </Text>
        </Pressable>
    );
});

// One project = one tap target. Opens the most-recent session under this path.
// Long-press → existing session actions (archive, etc.) on the lead session.
const ProjectTile = React.memo(({ group, selected, isFirst, isLast }: {
    group: ProjectGroup;
    selected: boolean;
    isFirst: boolean;
    isLast: boolean;
}) => {
    const styles = stylesheet;
    const { theme } = useUnistyles();
    const router = useRouter();
    const draft = useNewSessionDraft();
    const navigateToSession = useNavigateToSession();
    const [actionsAnchor, setActionsAnchor] = React.useState<SessionActionsAnchor | null>(null);

    // Most-recent session is the tap target; the lead session drives the status dot.
    const mostRecent = React.useMemo(
        () => [...group.sessions].sort((a, b) => (b.createdAt ?? 0) - (a.createdAt ?? 0))[0],
        [group.sessions],
    );
    const lead = React.useMemo(() => pickLeadSession(group.sessions), [group.sessions]);

    const gitStatus = useSessionGitStatus(lead.id);
    const sessionPath = lead.path || '';
    const isWorktree = isWorktreePath(sessionPath);
    const worktreeName = isWorktree ? getWorktreeName(sessionPath) : null;
    const branch = worktreeName || (gitStatus?.lastUpdatedAt ? gitStatus.branch : null);
    const linesAdded = gitStatus?.unstagedLinesAdded ?? 0;
    const linesRemoved = gitStatus?.unstagedLinesRemoved ?? 0;

    const statusColor = lead.hasUnread
        ? { color: '#007AFF', pulsing: false }
        : STATUS_COLOR[lead.state];

    const statusLabel = React.useMemo(() => {
        if (lead.hasUnread) return t('status.unread');
        if (lead.state === 'thinking') {
            return vibingMessages[Math.floor(Math.random() * vibingMessages.length)].toLowerCase() + '…';
        }
        if (lead.state === 'permission_required') return t('status.permissionRequired');
        if (lead.state === 'waiting') return t('status.online');
        return null;
    }, [lead.state, lead.hasUnread]);

    const handlePress = React.useCallback(() => {
        navigateToSession(mostRecent.id);
    }, [navigateToSession, mostRecent.id]);

    const handleAdd = React.useCallback((e: any) => {
        e.stopPropagation?.();
        const repoPath = isWorktree ? getRepoPath(sessionPath) : sessionPath;
        if (lead.machineId) draft.setMachineId(lead.machineId);
        draft.setPath(formatPathRelativeToHome(repoPath, lead.homeDir ?? undefined));
        draft.setSessionType(isWorktree ? 'worktree' : 'simple');
        draft.setWorktreeKey(isWorktree ? sessionPath : null);
        router.navigate('/new');
    }, [lead.machineId, lead.homeDir, sessionPath, isWorktree, draft, router]);

    const handleContextMenu = React.useCallback((event: any) => {
        event.preventDefault?.();
        event.stopPropagation?.();
        setActionsAnchor({
            type: 'point',
            x: event.nativeEvent.clientX ?? event.nativeEvent.pageX ?? 0,
            y: event.nativeEvent.clientY ?? event.nativeEvent.pageY ?? 0,
        });
    }, []);

    const showActionAlert = useSessionActionAlert(mostRecent.id);
    const menuProps = Platform.OS === 'web'
        ? ({ onContextMenu: handleContextMenu } as any)
        : { onLongPress: showActionAlert };

    return (
        <View style={[
            styles.tileWrapper,
            isFirst && styles.tileWrapperFirst,
            isLast && styles.tileWrapperLast,
        ]}>
            <Pressable
                style={[
                    styles.tile,
                    selected && styles.tileSelected,
                    isFirst && styles.tileFirst,
                    isLast && styles.tileLast,
                ]}
                onPress={handlePress}
                {...menuProps}
            >
                <View style={styles.tileMain}>
                    <View style={styles.tileTitleRow}>
                        <Text style={styles.tileTitle} numberOfLines={1}>
                            {group.projectName || group.displayPath}
                        </Text>
                        {group.sessions.length > 1 && (
                            <View style={styles.sessionCountBadge}>
                                <Text style={styles.sessionCountText}>{group.sessions.length}</Text>
                            </View>
                        )}
                    </View>

                    {(group.parentDir || branch) && (
                        <View style={styles.tileMetaRow}>
                            {group.parentDir ? (
                                <Text style={styles.tileMetaText} numberOfLines={1}>
                                    {group.parentDir}
                                </Text>
                            ) : null}
                            {branch && (
                                <>
                                    {group.parentDir ? <Text style={styles.tileMetaDot}>·</Text> : null}
                                    <Text style={styles.tileBranch} numberOfLines={1}>
                                        {branch}
                                    </Text>
                                    {isWorktree && (
                                        <MaterialCommunityIcons
                                            name="tree"
                                            size={11}
                                            color={theme.colors.textSecondary}
                                            style={{ marginLeft: 3 }}
                                        />
                                    )}
                                    {linesAdded > 0 && <Text style={styles.tileAdded}>+{linesAdded}</Text>}
                                    {linesRemoved > 0 && <Text style={styles.tileRemoved}>-{linesRemoved}</Text>}
                                </>
                            )}
                        </View>
                    )}

                    {statusLabel && (
                        <Text style={[styles.tileStatusLabel, { color: statusColor.color }]} numberOfLines={1}>
                            {statusLabel}
                        </Text>
                    )}
                </View>

                <View style={styles.tileRight}>
                    <StatusDot color={statusColor.color} isPulsing={statusColor.pulsing} />
                    <Pressable
                        onPress={handleAdd}
                        hitSlop={{ top: 12, bottom: 12, left: 12, right: 12 }}
                        style={styles.tileAddButton}
                    >
                        <Ionicons name="add" size={18} color={theme.colors.textSecondary} />
                    </Pressable>
                </View>
            </Pressable>

            {Platform.OS === 'web' && (
                <SessionActionsPopover
                    anchor={actionsAnchor}
                    onClose={() => setActionsAnchor(null)}
                    sessionId={mostRecent.id}
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

            const projectPath = session.path || '';
            let pg = mg.projects.find(p => p.projectPath === projectPath);
            if (!pg) {
                const displayPath = formatPathRelativeToHome(projectPath, session.homeDir ?? undefined);
                const segments = displayPath.split(/[/\\]/).filter(Boolean);
                const projectName = segments.length > 0 ? segments[segments.length - 1] : displayPath;
                const parentDir = segments.length > 1
                    ? (displayPath.startsWith('~') ? '~/' : '') + segments.slice(0, -1).join('/')
                    : (displayPath.startsWith('~') && segments.length <= 1 ? '~' : '');
                pg = { projectPath, displayPath, projectName, parentDir, sessions: [] };
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
            {machineGroups.map(mg => {
                const projectCount = mg.projects.length;
                return (
                    <View key={mg.machineId} style={styles.machineSection}>
                        <MachineHeader
                            machineName={mg.machineName}
                            machineId={mg.machineId}
                            count={projectCount}
                        />
                        <View style={styles.tileGroup}>
                            {mg.projects.map((pg, idx) => {
                                const tileSelected = !!selectedSessionId
                                    && pg.sessions.some(s => s.id === selectedSessionId);
                                return (
                                    <ProjectTile
                                        key={pg.projectPath}
                                        group={pg}
                                        selected={tileSelected}
                                        isFirst={idx === 0}
                                        isLast={idx === mg.projects.length - 1}
                                    />
                                );
                            })}
                        </View>
                    </View>
                );
            })}
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
    machineHeaderIcon: {
        marginRight: 7,
    },
    machineHeaderName: {
        flex: 1,
        fontSize: 17,
        color: theme.colors.text,
        ...Typography.default('semiBold'),
        letterSpacing: -0.2,
    },
    machineHeaderCount: {
        fontSize: 13,
        color: theme.colors.textSecondary,
        ...Typography.default('regular'),
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
    tileWrapperFirst: {},
    tileWrapperLast: {},
    tile: {
        minHeight: 64,
        flexDirection: 'row',
        alignItems: 'center',
        paddingHorizontal: 16,
        paddingVertical: 10,
        borderBottomWidth: StyleSheet.hairlineWidth,
        borderBottomColor: theme.colors.divider,
    },
    tileFirst: {},
    tileLast: {
        borderBottomWidth: 0,
    },
    tileSelected: {
        backgroundColor: theme.colors.surfaceSelected,
    },
    tileMain: {
        flex: 1,
        justifyContent: 'center',
        minWidth: 0,
    },
    tileTitleRow: {
        flexDirection: 'row',
        alignItems: 'center',
    },
    tileTitle: {
        fontSize: 16,
        color: theme.colors.text,
        ...Typography.default('semiBold'),
        letterSpacing: -0.1,
        flexShrink: 1,
    },
    sessionCountBadge: {
        marginLeft: 8,
        paddingHorizontal: 6,
        paddingVertical: 1,
        borderRadius: 9,
        backgroundColor: theme.colors.divider,
        minWidth: 18,
        alignItems: 'center',
    },
    sessionCountText: {
        fontSize: 11,
        color: theme.colors.textSecondary,
        ...Typography.default('semiBold'),
    },
    tileMetaRow: {
        flexDirection: 'row',
        alignItems: 'center',
        marginTop: 2,
        flexWrap: 'nowrap',
    },
    tileMetaText: {
        fontSize: 12,
        color: theme.colors.textSecondary,
        ...Typography.default('regular'),
        flexShrink: 1,
    },
    tileMetaDot: {
        fontSize: 12,
        color: theme.colors.textSecondary,
        marginHorizontal: 5,
    },
    tileBranch: {
        fontSize: 12,
        color: theme.colors.textSecondary,
        ...Typography.default('regular'),
        flexShrink: 1,
    },
    tileAdded: {
        fontSize: 11,
        color: theme.colors.gitAddedText,
        marginLeft: 6,
        ...Typography.default('semiBold'),
    },
    tileRemoved: {
        fontSize: 11,
        color: theme.colors.gitRemovedText,
        marginLeft: 3,
        ...Typography.default('semiBold'),
    },
    tileStatusLabel: {
        fontSize: 11,
        marginTop: 3,
        ...Typography.default('regular'),
    },
    tileRight: {
        flexDirection: 'row',
        alignItems: 'center',
        marginLeft: 10,
        gap: 8,
    },
    tileAddButton: {
        padding: 4,
    },
}));
