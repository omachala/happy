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

    // Always yolo. Ignore session.permissionMode and settings overrides
    // entirely — this user never wants an agent to ask for permission, so the
    // hardcoded per-flavor default (bypassPermissions / yolo) is the only
    // value we ever send. Stored 'plan' / 'default' / etc. from older sessions
    // or auto-switches (e.g. EnterPlanMode tool) are deliberately clobbered.
    meta.permissionMode = codeDefaults.permissionMode;

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
