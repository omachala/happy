import { describe, it, expect } from 'vitest';
import { parseUsageUpdate, type SessionUpdate } from './sessionUpdateHandlers';

describe('parseUsageUpdate', () => {
  it('parses the payload opencode actually emits', () => {
    // Captured verbatim from a live `opencode acp` session.
    const update = {
      sessionUpdate: 'usage_update',
      used: 22848,
      size: 200000,
      cost: { amount: 0, currency: 'USD' },
    } as SessionUpdate;

    expect(parseUsageUpdate(update)).toEqual({
      type: 'usage',
      used: 22848,
      size: 200000,
      costUsd: 0,
    });
  });

  it('omits cost when it is absent or not USD', () => {
    const base = { sessionUpdate: 'usage_update', used: 10, size: 100 };

    expect(parseUsageUpdate(base as SessionUpdate)).toEqual({ type: 'usage', used: 10, size: 100 });
    expect(parseUsageUpdate({ ...base, cost: { amount: 3, currency: 'EUR' } } as SessionUpdate))
      .toEqual({ type: 'usage', used: 10, size: 100 });
  });

  it('rejects payloads that cannot produce a meaningful ratio', () => {
    const base = { sessionUpdate: 'usage_update', used: 10, size: 100 };

    // A zero or negative denominator would make the app divide by zero.
    expect(parseUsageUpdate({ ...base, size: 0 } as SessionUpdate)).toBeNull();
    expect(parseUsageUpdate({ ...base, size: -1 } as SessionUpdate)).toBeNull();
    expect(parseUsageUpdate({ ...base, size: null } as unknown as SessionUpdate)).toBeNull();
    expect(parseUsageUpdate({ ...base, used: -1 } as SessionUpdate)).toBeNull();
    expect(parseUsageUpdate({ ...base, used: undefined } as SessionUpdate)).toBeNull();
    expect(parseUsageUpdate({ ...base, used: '10' } as unknown as SessionUpdate)).toBeNull();
    expect(parseUsageUpdate({ ...base, size: Number.NaN } as SessionUpdate)).toBeNull();
    expect(parseUsageUpdate({ ...base, used: Number.POSITIVE_INFINITY } as SessionUpdate)).toBeNull();
  });
});
