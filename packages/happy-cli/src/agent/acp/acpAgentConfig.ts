import { OPENCODE_MODEL_POLICY, type AcpModelPolicy } from './acpModelPolicy';

export type AcpAgentConfig = {
  command: string;
  args: string[];
  /**
   * Only one session of this agent may run per machine. Set for agents backed by a
   * single-slot local model server, where a second session queues invisibly instead of failing.
   */
  exclusive?: boolean;
  /**
   * Restricts the models this agent advertises to the app and pins the model selected at
   * session start. Only attached to first-class agents, never to the `happy acp -- <cmd>`
   * passthrough form, which is a deliberate override.
   */
  modelPolicy?: AcpModelPolicy;
};

export const KNOWN_ACP_AGENTS: Record<string, AcpAgentConfig> = {
  gemini: { command: 'gemini', args: ['--experimental-acp'] },
  opencode: { command: 'opencode', args: ['acp'], exclusive: true, modelPolicy: OPENCODE_MODEL_POLICY },
};

export type ResolvedAcpAgentConfig = {
  agentName: string;
  command: string;
  args: string[];
  exclusive?: boolean;
  modelPolicy?: AcpModelPolicy;
};

export function resolveAcpAgentConfig(cliArgs: string[]): ResolvedAcpAgentConfig {
  if (cliArgs.length === 0) {
    throw new Error('Usage: happy acp <agent-name> or happy acp -- <command> [args]');
  }

  if (cliArgs[0] === '--') {
    const command = cliArgs[1];
    if (!command) {
      throw new Error('Missing command after "--". Usage: happy acp -- <command> [args]');
    }
    return {
      agentName: command,
      command,
      args: cliArgs.slice(2),
    };
  }

  const agentName = cliArgs[0];
  const known = KNOWN_ACP_AGENTS[agentName];
  if (known) {
    const passthroughArgs = cliArgs
      .slice(1)
      // Backward-compatible with old OpenCode docs/flags.
      .filter((arg) => !(agentName === 'opencode' && arg === '--acp'));
    return {
      agentName,
      command: known.command,
      args: [...known.args, ...passthroughArgs],
      exclusive: known.exclusive,
      modelPolicy: known.modelPolicy,
    };
  }

  return {
    agentName,
    command: agentName,
    args: cliArgs.slice(1),
  };
}
