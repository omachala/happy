import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mockConfiguration = vi.hoisted(() => ({
  happyHomeDir: '',
  currentCliVersion: '1.2.3-test',
  // Read by the logger at import time via getSessionLogPath().
  logsDir: '/tmp',
  isDaemonProcess: false,
}));

vi.mock('@/configuration', () => ({
  configuration: mockConfiguration,
}));

const { acquireExclusiveAgentLock, ExclusiveAgentLockError } = await import('./exclusiveAgentLock');

describe('acquireExclusiveAgentLock', () => {
  let home: string;

  beforeEach(() => {
    home = mkdtempSync(join(tmpdir(), 'happy-lock-'));
    mockConfiguration.happyHomeDir = home;
  });

  afterEach(() => {
    rmSync(home, { recursive: true, force: true });
  });

  const lockFile = () => join(home, 'opencode.exclusive.lock');

  it('creates a lock file describing the holder, and removes it on release', async () => {
    const lock = await acquireExclusiveAgentLock('opencode');

    expect(existsSync(lockFile())).toBe(true);
    const holder = JSON.parse(readFileSync(lockFile(), 'utf8'));
    expect(holder.pid).toBe(process.pid);
    expect(holder.cliVersion).toBe('1.2.3-test');
    expect(typeof holder.startedAt).toBe('number');

    await lock.release();
    expect(existsSync(lockFile())).toBe(false);
  });

  it('refuses a second acquire while a live process holds it, naming the holder', async () => {
    const lock = await acquireExclusiveAgentLock('opencode');

    // process.pid is by definition alive, so this exercises the liveness path.
    await expect(acquireExclusiveAgentLock('opencode')).rejects.toThrow(ExclusiveAgentLockError);
    await expect(acquireExclusiveAgentLock('opencode')).rejects.toThrow(String(process.pid));

    await lock.release();
    // Once released the slot is free again.
    await (await acquireExclusiveAgentLock('opencode')).release();
  });

  it('reclaims a lock whose owning process is gone', async () => {
    // PID 2^22 is above Linux's default pid_max, so it can never be live.
    writeFileSync(lockFile(), JSON.stringify({
      pid: 4194304,
      cwd: '/somewhere',
      startedAt: Date.now(),
      cliVersion: '0.0.0',
    }));

    const lock = await acquireExclusiveAgentLock('opencode');
    expect(JSON.parse(readFileSync(lockFile(), 'utf8')).pid).toBe(process.pid);
    await lock.release();
  });

  it('does NOT reclaim on age alone', async () => {
    // A cold 32k prefill takes ~80s with the lock file untouched. An mtime-based staleness rule
    // would steal the lock mid-generation; liveness must win over age.
    writeFileSync(lockFile(), JSON.stringify({
      pid: process.pid,
      cwd: '/somewhere',
      startedAt: Date.now() - 10 * 60 * 1000,
      cliVersion: '0.0.0',
    }));

    await expect(acquireExclusiveAgentLock('opencode')).rejects.toThrow(ExclusiveAgentLockError);
  });

  it('steals a live lock when forced', async () => {
    writeFileSync(lockFile(), JSON.stringify({
      pid: process.pid,
      cwd: '/somewhere',
      startedAt: Date.now(),
      cliVersion: '0.0.0',
    }));

    const lock = await acquireExclusiveAgentLock('opencode', { force: true });
    expect(JSON.parse(readFileSync(lockFile(), 'utf8')).cliVersion).toBe('1.2.3-test');
    await lock.release();
  });

  it('reclaims a corrupt lock file', async () => {
    writeFileSync(lockFile(), 'not json at all');

    const lock = await acquireExclusiveAgentLock('opencode');
    expect(JSON.parse(readFileSync(lockFile(), 'utf8')).pid).toBe(process.pid);
    await lock.release();
  });

  it('keys the lock by agent name', async () => {
    const opencode = await acquireExclusiveAgentLock('opencode');
    // A different agent must not be blocked by opencode's lock.
    const other = await acquireExclusiveAgentLock('some-other-agent');

    expect(existsSync(join(home, 'some-other-agent.exclusive.lock'))).toBe(true);
    await opencode.release();
    await other.release();
  });
});
