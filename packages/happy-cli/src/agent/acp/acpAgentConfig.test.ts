import { describe, expect, it } from 'vitest';
import { KNOWN_ACP_AGENTS, resolveAcpAgentConfig } from './acpAgentConfig';
import { OPENCODE_MODEL_POLICY } from './acpModelPolicy';

describe('KNOWN_ACP_AGENTS', () => {
  it('defines built-in Gemini and OpenCode command mappings', () => {
    expect(KNOWN_ACP_AGENTS).toEqual({
      gemini: { command: 'gemini', args: ['--experimental-acp'] },
      opencode: { command: 'opencode', args: ['acp'], exclusive: true, modelPolicy: OPENCODE_MODEL_POLICY },
    });
  });
});

describe('model policy attachment', () => {
  it('attaches the OpenCode model policy only to the first-class opencode agent', () => {
    expect(resolveAcpAgentConfig(['opencode']).modelPolicy).toEqual(OPENCODE_MODEL_POLICY);
    expect(resolveAcpAgentConfig(['gemini']).modelPolicy).toBeUndefined();
    expect(resolveAcpAgentConfig(['my-agent']).modelPolicy).toBeUndefined();
  });

  it('does not attach a model policy through the -- passthrough form', () => {
    // `happy acp -- opencode acp` is a deliberate override; the user gets the raw model list.
    expect(resolveAcpAgentConfig(['--', 'opencode', 'acp']).modelPolicy).toBeUndefined();
  });
});

describe('exclusive agents', () => {
  it('marks opencode exclusive but leaves gemini unaffected', () => {
    expect(resolveAcpAgentConfig(['opencode']).exclusive).toBe(true);
    expect(resolveAcpAgentConfig(['gemini']).exclusive).toBeUndefined();
  });

  it('does not inherit exclusivity through the -- passthrough form', () => {
    // `happy acp -- opencode acp` is a deliberate override, so it must not take the lock.
    expect(resolveAcpAgentConfig(['--', 'opencode', 'acp']).exclusive).toBeUndefined();
  });
});

describe('resolveAcpAgentConfig', () => {
  it('resolves known agent names to predefined command + args', () => {
    expect(resolveAcpAgentConfig(['gemini'])).toEqual({
      agentName: 'gemini',
      command: 'gemini',
      args: ['--experimental-acp'],
    });
  });

  it('appends extra CLI args for known agent aliases', () => {
    expect(resolveAcpAgentConfig(['opencode', '--foo'])).toEqual({
      agentName: 'opencode',
      command: 'opencode',
      args: ['acp', '--foo'],
      exclusive: true,
      modelPolicy: OPENCODE_MODEL_POLICY,
    });
  });

  it('strips legacy --acp for opencode compatibility', () => {
    expect(resolveAcpAgentConfig(['opencode', '--acp', '--foo'])).toEqual({
      agentName: 'opencode',
      command: 'opencode',
      args: ['acp', '--foo'],
      exclusive: true,
      modelPolicy: OPENCODE_MODEL_POLICY,
    });
  });

  it('resolves custom command form with -- separator', () => {
    expect(resolveAcpAgentConfig(['--', 'custom-agent', '--flag'])).toEqual({
      agentName: 'custom-agent',
      command: 'custom-agent',
      args: ['--flag'],
    });
  });

  it('treats unknown agent names as direct commands', () => {
    expect(resolveAcpAgentConfig(['my-agent', '--x'])).toEqual({
      agentName: 'my-agent',
      command: 'my-agent',
      args: ['--x'],
    });
  });

  it('throws with helpful usage when no args are provided', () => {
    expect(() => resolveAcpAgentConfig([])).toThrow('Usage: happy acp <agent-name> or happy acp -- <command> [args]');
  });

  it('throws when separator form omits command', () => {
    expect(() => resolveAcpAgentConfig(['--'])).toThrow('Missing command after "--". Usage: happy acp -- <command> [args]');
  });
});
