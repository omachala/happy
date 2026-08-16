import { describe, expect, it } from 'vitest';
import type { SessionConfigOption, SessionConfigSelectOption, SessionModelState } from '@agentclientprotocol/sdk';
import {
  OPENCODE_MODEL_POLICY,
  applyAcpModelPolicyToConfigOptions,
  applyAcpModelPolicyToModelState,
} from './acpModelPolicy';
import { mergeAcpSessionConfigIntoMetadata } from './sessionConfigMetadata';

const CARA_MODEL_ID = 'cara/qwen3.8-27b';
const CARA_MODEL_NAME = 'Cara Qwen3.8-27B/Qwen3.8-27B Q3_K_M (MTP-2, 32K)';

/** Mirrors the 22 hosted "OpenCode Zen" models opencode advertises alongside the local one. */
const ZEN_MODEL_IDS = [
  'opencode/big-pickle',
  'opencode/nemotron-1',
  'opencode/nemotron-2',
  'opencode/nemotron-3',
  'opencode/nemotron-4',
  'opencode/mimo-1',
  'opencode/mimo-2',
  'opencode/mimo-3',
  'opencode/mimo-4',
  'opencode/laguna-1',
  'opencode/laguna-2',
  'opencode/laguna-3',
  'opencode/laguna-4',
  'opencode/hy3-1',
  'opencode/hy3-2',
  'opencode/hy3-3',
  'opencode/hy3-4',
  'opencode/deepseek-1',
  'opencode/deepseek-2',
  'opencode/deepseek-3',
  'opencode/deepseek-4',
  'opencode/deepseek-5',
];

function selectOption(value: string, name = value): SessionConfigSelectOption {
  return { value, name };
}

function opencodeModelConfigOption(): SessionConfigOption {
  return {
    type: 'select',
    id: 'model',
    name: 'Model',
    category: 'model',
    currentValue: 'opencode/big-pickle',
    options: [selectOption(CARA_MODEL_ID, CARA_MODEL_NAME), ...ZEN_MODEL_IDS.map((id) => selectOption(id))],
  };
}

function modeConfigOption(): SessionConfigOption {
  return {
    type: 'select',
    id: 'permission-mode',
    name: 'Mode',
    category: 'mode',
    currentValue: 'build',
    options: [selectOption('build', 'Build'), selectOption('plan', 'Plan')],
  };
}

describe('applyAcpModelPolicyToConfigOptions', () => {
  it('filters the 23 advertised opencode models down to the single cara entry', () => {
    const outcome = applyAcpModelPolicyToConfigOptions(
      [modeConfigOption(), opencodeModelConfigOption()],
      OPENCODE_MODEL_POLICY,
    );

    expect(outcome.fellBack).toBe(false);
    expect(outcome.removedCount).toBe(22);

    const modelOption = outcome.value[1]!;
    expect(modelOption.options).toEqual([selectOption(CARA_MODEL_ID, CARA_MODEL_NAME)]);
    expect(modelOption.currentValue).toBe(CARA_MODEL_ID);
  });

  it('leaves non-model config options untouched', () => {
    const mode = modeConfigOption();
    const outcome = applyAcpModelPolicyToConfigOptions([mode, opencodeModelConfigOption()], OPENCODE_MODEL_POLICY);
    expect(outcome.value[0]).toBe(mode);
  });

  it('keeps an allowed current value that the agent already reported', () => {
    const option = opencodeModelConfigOption();
    option.currentValue = CARA_MODEL_ID;
    const outcome = applyAcpModelPolicyToConfigOptions([option], OPENCODE_MODEL_POLICY);
    expect(outcome.value[0]!.currentValue).toBe(CARA_MODEL_ID);
  });

  it('filters inside option groups and drops groups that become empty', () => {
    const grouped: SessionConfigOption = {
      type: 'select',
      id: 'model',
      name: 'Model',
      category: 'model',
      currentValue: 'opencode/big-pickle',
      options: [
        { group: 'local', name: 'Local', options: [selectOption(CARA_MODEL_ID, CARA_MODEL_NAME)] },
        { group: 'zen', name: 'OpenCode Zen', options: ZEN_MODEL_IDS.map((id) => selectOption(id)) },
      ],
    };

    const outcome = applyAcpModelPolicyToConfigOptions([grouped], OPENCODE_MODEL_POLICY);
    expect(outcome.fellBack).toBe(false);
    expect(outcome.value[0]!.options).toEqual([
      { group: 'local', name: 'Local', options: [selectOption(CARA_MODEL_ID, CARA_MODEL_NAME)] },
    ]);
    expect(outcome.value[0]!.currentValue).toBe(CARA_MODEL_ID);
  });

  it('falls back to the unfiltered list when no model matches the policy', () => {
    const option = opencodeModelConfigOption();
    option.options = ZEN_MODEL_IDS.map((id) => selectOption(id));

    const outcome = applyAcpModelPolicyToConfigOptions([option], OPENCODE_MODEL_POLICY);

    expect(outcome.fellBack).toBe(true);
    expect(outcome.removedCount).toBe(0);
    expect(outcome.value[0]).toBe(option);
    expect(outcome.value[0]!.options).toHaveLength(22);
  });

  it('selects the first surviving model when the preferred one is gone', () => {
    const option = opencodeModelConfigOption();
    option.options = [selectOption('cara/other-model'), ...ZEN_MODEL_IDS.map((id) => selectOption(id))];

    const outcome = applyAcpModelPolicyToConfigOptions([option], OPENCODE_MODEL_POLICY);

    expect(outcome.fellBack).toBe(false);
    expect(outcome.value[0]!.currentValue).toBe('cara/other-model');
  });

  it('is a no-op for agents without a policy - gemini config options are never filtered', () => {
    // Gemini never reaches applyAcpModelPolicy* because runAcp only calls it when opts.modelPolicy
    // is set; this asserts the equivalent behaviour of a policy that allows everything.
    const geminiModels: SessionConfigOption = {
      type: 'select',
      id: 'model',
      name: 'Model',
      category: 'model',
      currentValue: 'gemini-2.5-pro',
      options: [selectOption('gemini-2.5-pro'), selectOption('gemini-2.5-flash')],
    };

    const outcome = applyAcpModelPolicyToConfigOptions([geminiModels], OPENCODE_MODEL_POLICY);
    expect(outcome.fellBack).toBe(true);
    expect(outcome.value[0]).toBe(geminiModels);
  });
});

describe('applyAcpModelPolicyToModelState', () => {
  const modelState = (): SessionModelState => ({
    currentModelId: 'opencode/big-pickle',
    availableModels: [
      { modelId: CARA_MODEL_ID, name: CARA_MODEL_NAME },
      ...ZEN_MODEL_IDS.map((id) => ({ modelId: id, name: id })),
    ],
  });

  it('filters the legacy model state down to the cara entry and pins the current model', () => {
    const outcome = applyAcpModelPolicyToModelState(modelState(), OPENCODE_MODEL_POLICY);

    expect(outcome.fellBack).toBe(false);
    expect(outcome.removedCount).toBe(22);
    expect(outcome.value.availableModels).toEqual([{ modelId: CARA_MODEL_ID, name: CARA_MODEL_NAME }]);
    expect(outcome.value.currentModelId).toBe(CARA_MODEL_ID);
  });

  it('falls back to the unfiltered state when no model matches', () => {
    const models: SessionModelState = {
      currentModelId: 'opencode/big-pickle',
      availableModels: ZEN_MODEL_IDS.map((id) => ({ modelId: id, name: id })),
    };

    const outcome = applyAcpModelPolicyToModelState(models, OPENCODE_MODEL_POLICY);

    expect(outcome.fellBack).toBe(true);
    expect(outcome.value).toBe(models);
  });
});

describe('policy output reaching session metadata', () => {
  it('publishes only the cara model and marks it current', () => {
    const outcome = applyAcpModelPolicyToConfigOptions([opencodeModelConfigOption()], OPENCODE_MODEL_POLICY);
    const metadata = mergeAcpSessionConfigIntoMetadata({} as never, { configOptions: outcome.value });

    expect(metadata.models).toEqual([{ code: CARA_MODEL_ID, value: CARA_MODEL_NAME }]);
    expect(metadata.currentModelCode).toBe(CARA_MODEL_ID);
  });
});
