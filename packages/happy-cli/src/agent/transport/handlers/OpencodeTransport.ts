/**
 * OpenCode Transport Handler
 *
 * OpenCode-specific implementation of TransportHandler.
 *
 * OpenCode is routinely pointed at a local model (llama.cpp / Ollama / LM Studio) rather than a
 * hosted frontier model. Local generation is an order of magnitude slower — a 27B Q3 model on a
 * single consumer GPU produces roughly 30 tokens/second, and prompt prefill on a full context can
 * take over a minute. The default 500 ms idle window is far too tight for that: it fires between
 * ordinary chunks and around every tool round-trip, which makes the session look like it keeps
 * going idle mid-answer.
 *
 * Only the idle window is overridden; everything else inherits DefaultTransport.
 *
 * @module OpencodeTransport
 */

import { DefaultTransport } from '../DefaultTransport';

/**
 * OpenCode-specific timeout values (in milliseconds)
 */
export const OPENCODE_TIMEOUTS = {
  /**
   * Idle detection after the last message chunk.
   *
   * Sized for local inference: long enough to span a slow model's inter-chunk gaps and tool
   * round-trips, short enough that the thinking indicator still drops promptly once the agent
   * really has stopped. Turn completion does not depend on this value — the turn ends when the
   * ACP `session/prompt` request resolves.
   */
  idle: 15_000,
} as const;

/**
 * OpenCode transport handler.
 */
export class OpencodeTransport extends DefaultTransport {
  constructor() {
    super('opencode');
  }

  getIdleTimeout(): number {
    return OPENCODE_TIMEOUTS.idle;
  }
}

/**
 * Singleton instance for convenience
 */
export const opencodeTransport = new OpencodeTransport();
