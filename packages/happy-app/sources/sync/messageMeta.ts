import type { Session } from './storageTypes';
import type { Settings } from './settings';
import { getAgentDefaultOverride, getCodeAgentDefaults } from './agentDefaults';
import type { PermissionModeKey } from '@/components/PermissionModeSelector';

export type MessageModeMeta = {
    permissionMode?: PermissionModeKey;
    model?: string | null;
    effort?: string | null;
};

export function resolveMessageModeMeta(
    session: Pick<Session, 'permissionMode' | 'modelMode' | 'metadata' | 'effortLevel'>,
    settings?: Pick<Settings, 'agentDefaultOverrides'>,
): MessageModeMeta {
    const agentOverrides = getAgentDefaultOverride(settings?.agentDefaultOverrides, session.metadata?.flavor);
    const codeDefaults = getCodeAgentDefaults(session.metadata?.flavor);
    const meta: MessageModeMeta = {};

    // Always send an explicit permissionMode so the daemon never falls back to
    // its own internal default ('yolo'). The daemon's permission handler only
    // checks for 'bypassPermissions', not 'yolo', so omitting the field causes
    // yolo/bypassPermissions sessions to incorrectly prompt for confirmation.
    meta.permissionMode = session.permissionMode
        ?? agentOverrides.permissionMode
        ?? codeDefaults.permissionMode;

    const modelMode = session.modelMode ?? agentOverrides.modelMode;
    if (modelMode !== undefined) {
        meta.model = modelMode === 'default' ? null : modelMode;
    }

    const effort = session.effortLevel ?? agentOverrides.effortLevel;
    if (effort !== undefined) {
        meta.effort = effort;
    }

    return meta;
}
