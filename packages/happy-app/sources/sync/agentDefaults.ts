import * as z from 'zod';

export const agentKeys = ['claude', 'codex', 'gemini', 'openclaw', 'agy', 'opencode'] as const;
export type AgentKey = typeof agentKeys[number];

export const AgentDefaultOverrideSchema = z.object({
    permissionMode: z.string().optional(),
    modelMode: z.string().optional(),
    effortLevel: z.string().optional(),
}).passthrough();

export const AgentDefaultOverridesSchema = z.object({
    claude: AgentDefaultOverrideSchema.optional(),
    codex: AgentDefaultOverrideSchema.optional(),
    gemini: AgentDefaultOverrideSchema.optional(),
    openclaw: AgentDefaultOverrideSchema.optional(),
    agy: AgentDefaultOverrideSchema.optional(),
    opencode: AgentDefaultOverrideSchema.optional(),
}).passthrough().default({});

export type AgentDefaultOverride = z.infer<typeof AgentDefaultOverrideSchema>;
export type AgentDefaultOverrides = z.infer<typeof AgentDefaultOverridesSchema>;
export type AgentDefaultField = keyof Pick<AgentDefaultOverride, 'permissionMode' | 'modelMode' | 'effortLevel'>;

export type AgentDefaultConfig = {
    permissionMode: string;
    modelMode: string;
    effortLevel: string | null;
};

// Every agent runs in its equivalent of Yolo/bypass. The user never wants
// permission prompts. `resolveMessageModeMeta` also force-sends these values
// on every outgoing message so no stored session state can reintroduce a
// prompting mode.
const codeAgentDefaults: Record<AgentKey, AgentDefaultConfig> = {
    claude: { permissionMode: 'bypassPermissions', modelMode: 'claude-opus-5', effortLevel: 'medium' },
    codex: { permissionMode: 'yolo', modelMode: 'gpt-5.5', effortLevel: 'medium' },
    gemini: { permissionMode: 'yolo', modelMode: 'gemini-2.5-pro', effortLevel: null },
    openclaw: { permissionMode: 'bypassPermissions', modelMode: 'default', effortLevel: null },
    agy: { permissionMode: 'yolo', modelMode: 'Gemini 3.1 Pro (High)', effortLevel: null },
    // opencode runs against the local Cara Qwen only. Its live ACP mode list wins
    // over this default when the CLI reports one; `bypassPermissions` just keeps
    // the never-prompt invariant before the session has connected.
    opencode: { permissionMode: 'bypassPermissions', modelMode: 'cara/qwen3.8-27b', effortLevel: null },
};

export function normalizeAgentKey(flavor: string | null | undefined): AgentKey {
    if (flavor === 'codex' || flavor === 'gemini' || flavor === 'openclaw' || flavor === 'agy' || flavor === 'opencode') {
        return flavor;
    }
    return 'claude';
}

export function getCodeAgentDefaults(flavor: string | null | undefined): AgentDefaultConfig {
    return codeAgentDefaults[normalizeAgentKey(flavor)];
}

export function getAgentDefaultOverride(
    overrides: AgentDefaultOverrides | null | undefined,
    flavor: string | null | undefined,
): AgentDefaultOverride {
    return overrides?.[normalizeAgentKey(flavor)] ?? {};
}

export function resolveAgentDefaultConfig(
    overrides: AgentDefaultOverrides | null | undefined,
    flavor: string | null | undefined,
): AgentDefaultConfig {
    const codeDefaults = getCodeAgentDefaults(flavor);
    const userOverride = getAgentDefaultOverride(overrides, flavor);
    return {
        permissionMode: userOverride.permissionMode ?? codeDefaults.permissionMode,
        modelMode: userOverride.modelMode ?? codeDefaults.modelMode,
        effortLevel: userOverride.effortLevel ?? codeDefaults.effortLevel,
    };
}

export function hasAgentDefaultOverride(
    overrides: AgentDefaultOverrides | null | undefined,
    flavor: string | null | undefined,
    field: AgentDefaultField,
): boolean {
    return getAgentDefaultOverride(overrides, flavor)[field] !== undefined;
}

export function getAgentDefaultOverrideValue(
    overrides: AgentDefaultOverrides | null | undefined,
    flavor: string | null | undefined,
    field: AgentDefaultField,
): string | undefined {
    return getAgentDefaultOverride(overrides, flavor)[field];
}

export function setAgentDefaultOverride(
    overrides: AgentDefaultOverrides | null | undefined,
    flavor: string | null | undefined,
    field: AgentDefaultField,
    value: string | null | undefined,
): AgentDefaultOverrides {
    const key = normalizeAgentKey(flavor);
    const next: AgentDefaultOverrides = { ...(overrides ?? {}) };
    const current: AgentDefaultOverride = { ...(next[key] ?? {}) };

    if (value === null || value === undefined) {
        delete current[field];
    } else {
        current[field] = value;
    }

    if (current.permissionMode === undefined && current.modelMode === undefined && current.effortLevel === undefined) {
        delete next[key];
    } else {
        next[key] = current;
    }

    return next;
}
