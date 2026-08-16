import { describe, expect, it } from 'vitest';
import { claudeContextWindowForModel } from './claudeContextWindow';

describe('claudeContextWindowForModel', () => {
    it('returns 1M for a model id carrying the [1m] marker', () => {
        expect(claudeContextWindowForModel('claude-opus-4-5-20260614[1m]')).toBe(1_000_000);
    });

    it('returns 200k for a plain Claude model id', () => {
        expect(claudeContextWindowForModel('claude-opus-4-5-20260614')).toBe(200_000);
        expect(claudeContextWindowForModel('claude-sonnet-4-5-20250929')).toBe(200_000);
        expect(claudeContextWindowForModel('claude-haiku-4-5')).toBe(200_000);
        expect(claudeContextWindowForModel('claude-fable-5-0-20260701')).toBe(200_000);
    });

    it('matches the [1m] marker case-insensitively', () => {
        expect(claudeContextWindowForModel('CLAUDE-OPUS-4-5-20260614[1M]')).toBe(1_000_000);
        expect(claudeContextWindowForModel('Claude-Sonnet-4-5')).toBe(200_000);
    });

    it('returns undefined for undefined or unrecognised models so the app keeps its fallback', () => {
        expect(claudeContextWindowForModel(undefined)).toBeUndefined();
        expect(claudeContextWindowForModel('')).toBeUndefined();
        expect(claudeContextWindowForModel('gpt-5.2-codex')).toBeUndefined();
    });
});
