/**
 * Exclusive Agent Lock
 *
 * Machine-wide mutual exclusion for agents that cannot run concurrently.
 *
 * The motivating case is opencode pointed at a local llama-server: that server has a single slot
 * (`--parallel 1`), so a second session does not fail loudly — it silently queues behind the first
 * and appears to hang. Failing fast with a message naming the holder is far better than a session
 * that looks alive but never responds.
 *
 * Staleness is decided by process liveness (`kill(pid, 0)`), deliberately NOT by file mtime. A
 * cold 32k prefill takes ~80 s during which the lock file is untouched, so any mtime-based rule
 * (such as the 10 s one in persistence.ts `updateSettings`) would reclaim a lock that is very much
 * in use.
 *
 * @module exclusiveAgentLock
 */

import { open, readFile, unlink } from 'node:fs/promises';
import { constants, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { configuration } from '@/configuration';
import { logger } from '@/ui/logger';

/** Identity of the process currently holding a lock */
export interface ExclusiveAgentLockHolder {
  pid: number;
  cwd: string;
  startedAt: number;
  cliVersion: string;
}

/** A held lock. Release is idempotent and never throws. */
export interface ExclusiveAgentLock {
  release(): Promise<void>;
}

/** Thrown when the lock is held by a live process and `force` was not requested */
export class ExclusiveAgentLockError extends Error {
  readonly holder: ExclusiveAgentLockHolder;

  constructor(message: string, holder: ExclusiveAgentLockHolder) {
    super(message);
    this.name = 'ExclusiveAgentLockError';
    this.holder = holder;
  }
}

function lockPath(name: string): string {
  return join(configuration.happyHomeDir, `${name}.exclusive.lock`);
}

function describeAge(startedAt: number): string {
  const seconds = Math.max(0, Math.round((Date.now() - startedAt) / 1000));
  return seconds < 60 ? `${seconds}s ago` : `${Math.round(seconds / 60)}m ago`;
}

/**
 * Read the lock holder, returning null when the file is absent or unreadable/corrupt.
 * A corrupt lock is treated as reclaimable — it cannot name a live process to defer to.
 */
async function readHolder(path: string): Promise<ExclusiveAgentLockHolder | null> {
  try {
    const parsed: unknown = JSON.parse(await readFile(path, 'utf8'));
    const { pid, cwd, startedAt, cliVersion } = (parsed ?? {}) as Partial<ExclusiveAgentLockHolder>;
    if (typeof pid !== 'number' || !Number.isFinite(pid)) {
      return null;
    }
    return {
      pid,
      cwd: typeof cwd === 'string' ? cwd : 'unknown directory',
      startedAt: typeof startedAt === 'number' ? startedAt : Date.now(),
      cliVersion: typeof cliVersion === 'string' ? cliVersion : 'unknown',
    };
  } catch {
    return null;
  }
}

/** Whether a pid is still running. Signal 0 performs the permission/liveness check without sending. */
function isProcessAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (err) {
    // EPERM means the process exists but belongs to another user — still alive.
    return (err as NodeJS.ErrnoException).code === 'EPERM';
  }
}

/**
 * Acquire the machine-wide lock for `name`.
 *
 * Throws {@link ExclusiveAgentLockError} when a live process already holds it, unless `force` is
 * set, in which case the existing lock is stolen (the caller is expected to have told the user).
 */
export async function acquireExclusiveAgentLock(
  name: string,
  options: { force?: boolean } = {},
): Promise<ExclusiveAgentLock> {
  const path = lockPath(name);
  const payload: ExclusiveAgentLockHolder = {
    pid: process.pid,
    cwd: process.cwd(),
    startedAt: Date.now(),
    cliVersion: configuration.currentCliVersion,
  };

  let released = false;
  const release = async (): Promise<void> => {
    if (released) {
      return;
    }
    released = true;
    // Only remove the file if we still own it, so a --force steal is not undone by the loser's
    // own cleanup running afterwards.
    const current = await readHolder(path);
    if (current && current.pid !== process.pid) {
      return;
    }
    await unlink(path).catch(() => { });
  };

  // At most two passes: the second only runs after a stale or forced lock has been removed.
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const handle = await open(path, constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY);
      await handle.writeFile(JSON.stringify(payload));
      await handle.close();

      process.once('exit', () => {
        try {
          unlinkSync(path);
        } catch { }
      });

      logger.debug(`[exclusiveAgentLock] acquired ${name} (pid ${process.pid})`);
      return { release };
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== 'EEXIST') {
        throw err;
      }

      const holder = await readHolder(path);
      if (holder && isProcessAlive(holder.pid) && !options.force) {
        throw new ExclusiveAgentLockError(
          `${name} is already running on this machine (pid ${holder.pid}, ${holder.cwd}, started ${describeAge(holder.startedAt)}). `
          + `The local model server has a single slot; stop that session first, or pass --force to take it over.`,
          holder,
        );
      }

      const reason = !holder ? 'unreadable' : options.force ? 'forced' : `stale (pid ${holder.pid} is gone)`;
      logger.debug(`[exclusiveAgentLock] reclaiming ${name} lock: ${reason}`);
      await unlink(path).catch(() => { });
    }
  }

  throw new Error(`Failed to acquire the ${name} lock after reclaiming it; another process raced us.`);
}
