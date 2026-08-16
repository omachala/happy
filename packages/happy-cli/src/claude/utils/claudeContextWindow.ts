/**
 * Derives the context window size (in tokens) for a Claude model id.
 *
 * Claude Code never reports the context window in its usage payloads, so the
 * app falls back to a hardcoded denominator and shows "100% context used" for
 * 1M-context Opus sessions. We derive it here from the model id instead.
 *
 * Model ids carry a `[1m]` suffix marker when the long context beta is active
 * (e.g. `claude-opus-4-5-20260614[1m]`). Everything else in a recognised Claude
 * family gets the standard 200k window. Unrecognised or missing model ids
 * deliberately return `undefined` so the app keeps its own fallback rather than
 * rendering a confidently wrong denominator.
 */

const CLAUDE_LONG_CONTEXT_MARKER = '[1m]';
const CLAUDE_LONG_CONTEXT_WINDOW = 1_000_000;
const CLAUDE_DEFAULT_CONTEXT_WINDOW = 200_000;

/**
 * Families are matched by substring, mirroring the app's
 * `getClaudeFamilyKeyFromModelId`, so dated ids like
 * `claude-sonnet-4-5-20250929` collapse to their family.
 */
const CLAUDE_MODEL_FAMILIES = ['fable', 'opus', 'sonnet', 'haiku'] as const;

export function claudeContextWindowForModel(model: string | undefined): number | undefined {
    if (!model) {
        return undefined;
    }
    const id = model.toLowerCase();
    if (id.includes(CLAUDE_LONG_CONTEXT_MARKER)) {
        return CLAUDE_LONG_CONTEXT_WINDOW;
    }
    return CLAUDE_MODEL_FAMILIES.some((family) => id.includes(family))
        ? CLAUDE_DEFAULT_CONTEXT_WINDOW
        : undefined;
}
