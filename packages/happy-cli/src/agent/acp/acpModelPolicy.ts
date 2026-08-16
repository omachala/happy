/**
 * ACP model policy - restricts which models an ACP agent may advertise to the app,
 * and which model the CLI selects at session start.
 *
 * Motivation: OpenCode's ACP mode advertises every model it can reach (one local
 * `cara/...` model plus 22 hosted "OpenCode Zen" models) and reports a hosted model as
 * `currentValue` regardless of the `model` set in `~/.config/opencode/opencode.json`.
 * The app prefers `metadata.models` over any hardcoded list, so the list has to be
 * trimmed here, CLI-side, before it reaches metadata.
 *
 * Everything in this file is pure: it takes ACP payloads and returns filtered payloads
 * plus enough information for the caller to log what happened. Only agents that opt in
 * (see `KNOWN_ACP_AGENTS` in `@/agent/acp/acpAgentConfig`) get a policy, so gemini, the
 * `happy acp -- <cmd>` passthrough form, and every other agent are untouched.
 */

import type {
  SessionConfigOption,
  SessionConfigSelectGroup,
  SessionConfigSelectOption,
  SessionConfigSelectOptions,
  SessionModelState,
} from '@agentclientprotocol/sdk';

export type AcpModelPolicy = {
  /** Only models whose id starts with one of these prefixes are advertised to the app */
  allowedModelIdPrefixes: string[];
  /** Model selected explicitly at session start, instead of trusting the agent's advertised current value */
  preferredModelId: string;
};

/**
 * OpenCode runs against a local model server; the hosted "OpenCode Zen" models are noise
 * (and cost money) for this setup, so only the local `cara/` provider is exposed.
 */
export const OPENCODE_MODEL_POLICY: AcpModelPolicy = {
  allowedModelIdPrefixes: ['cara/'],
  preferredModelId: 'cara/qwen3.8-27b',
};

export type AcpModelPolicyOutcome<T> = {
  /** Payload to forward. Equals the input when the policy did not apply or fell back. */
  value: T;
  /** How many models the policy removed. Zero when the policy did not apply. */
  removedCount: number;
  /**
   * True when the policy matched zero models and the unfiltered payload was kept.
   * Emitting an empty list would leave the app's model picker with nothing to show.
   */
  fellBack: boolean;
};

function isAllowedModelId(modelId: string, policy: AcpModelPolicy): boolean {
  return policy.allowedModelIdPrefixes.some((prefix) => modelId.startsWith(prefix));
}

function isSelectGroup(entry: SessionConfigSelectOption | SessionConfigSelectGroup): entry is SessionConfigSelectGroup {
  return Array.isArray((entry as SessionConfigSelectGroup).options);
}

function isModelSelect(option: SessionConfigOption): boolean {
  if (option.type !== 'select') {
    return false;
  }
  if (option.category === 'model') {
    return true;
  }
  // Some ACP providers omit `category`; fall back to the same id/name heuristic runAcp uses.
  if (typeof option.category === 'string' && option.category.length > 0) {
    return false;
  }
  return option.id.toLowerCase().includes('model') || option.name.toLowerCase().includes('model');
}

/**
 * Picks the value the selector should report as current: keep the agent's own choice when it
 * survived filtering, otherwise the preferred model, otherwise the first surviving option.
 * A `currentValue` that is not present in `options` would break the app's picker.
 */
function resolveCurrentValue(keptValues: string[], advertised: string, policy: AcpModelPolicy): string {
  if (keptValues.includes(advertised)) {
    return advertised;
  }
  if (keptValues.includes(policy.preferredModelId)) {
    return policy.preferredModelId;
  }
  return keptValues[0]!;
}

export function applyAcpModelPolicyToConfigOptions(
  configOptions: SessionConfigOption[],
  policy: AcpModelPolicy,
): AcpModelPolicyOutcome<SessionConfigOption[]> {
  let removedCount = 0;
  let fellBack = false;

  const value = configOptions.map((option) => {
    if (!isModelSelect(option)) {
      return option;
    }

    const entries = option.options as Array<SessionConfigSelectOption | SessionConfigSelectGroup>;
    const keptFlat: SessionConfigSelectOption[] = [];
    const keptGroups: SessionConfigSelectGroup[] = [];
    const keptValues: string[] = [];
    let totalCount = 0;

    for (const entry of entries) {
      if (isSelectGroup(entry)) {
        totalCount += entry.options.length;
        const groupOptions = entry.options.filter((grouped) => isAllowedModelId(grouped.value, policy));
        if (groupOptions.length === 0) {
          continue;
        }
        keptGroups.push({ ...entry, options: groupOptions });
        for (const grouped of groupOptions) {
          keptValues.push(grouped.value);
        }
        continue;
      }

      totalCount += 1;
      if (!isAllowedModelId(entry.value, policy)) {
        continue;
      }
      keptFlat.push(entry);
      keptValues.push(entry.value);
    }

    if (keptValues.length === 0) {
      fellBack = true;
      return option;
    }

    removedCount += totalCount - keptValues.length;
    const filtered: SessionConfigSelectOptions = keptGroups.length > 0 ? keptGroups : keptFlat;
    return {
      ...option,
      options: filtered,
      currentValue: resolveCurrentValue(keptValues, option.currentValue, policy),
    };
  });

  return { value, removedCount, fellBack };
}

export function applyAcpModelPolicyToModelState(
  models: SessionModelState,
  policy: AcpModelPolicy,
): AcpModelPolicyOutcome<SessionModelState> {
  const kept = models.availableModels.filter((model) => isAllowedModelId(model.modelId, policy));
  if (kept.length === 0) {
    return { value: models, removedCount: 0, fellBack: true };
  }

  const keptValues = kept.map((model) => model.modelId);
  return {
    value: {
      ...models,
      availableModels: kept,
      currentModelId: resolveCurrentValue(keptValues, models.currentModelId, policy),
    },
    removedCount: models.availableModels.length - kept.length,
    fellBack: false,
  };
}
