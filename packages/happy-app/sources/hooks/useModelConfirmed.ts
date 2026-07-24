import * as React from 'react';
import { getClaudeFamilyKeyFromModelId } from '@/components/modelModeOptions';
import type { Metadata } from '@/sync/storageTypes';

/**
 * Tracks whether the current model selection has been *confirmed by the
 * server* during this component's lifetime — used to color the model chip
 * green (confirmed) vs gray (unconfirmed).
 *
 * On mount the chip is always gray, even if the cached metadata already
 * carries a matching `currentAgentModel`. Confirmation only fires when a
 * fresh metadata push arrives (new object identity from the sync store)
 * whose `currentAgentModel` collapses to the same family key as the
 * user's current selection. Any change to the selection resets back to
 * gray until the next server push arrives.
 *
 * happy-cli writes `currentAgentModel` on every turn boundary (in the
 * `result` handler of `claudeRemote.ts`), so the chip flips green as
 * soon as the agent finishes its first reply after opening the chat.
 */
export function useModelConfirmed(
    metadata: Metadata | null | undefined,
    selectedModelKey: string | undefined,
): boolean {
    const [confirmed, setConfirmed] = React.useState(false);
    const seenMetadataRef = React.useRef<Metadata | null | undefined>(undefined);

    // Reset to gray whenever the user changes the selected model. Also
    // rebase the ref to the current metadata so the effect below doesn't
    // immediately re-confirm from stale cached data — a new push must
    // arrive for the new selection to be confirmed.
    React.useEffect(() => {
        setConfirmed(false);
        seenMetadataRef.current = metadata;
        // Deliberately only depending on selectedModelKey — metadata is
        // captured as a side-effect, not tracked.
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [selectedModelKey]);

    React.useEffect(() => {
        if (seenMetadataRef.current === undefined) {
            // First render: treat whatever is already cached as "not fresh"
            // so the chip starts gray on mount / chat reopen.
            seenMetadataRef.current = metadata;
            return;
        }
        if (metadata === seenMetadataRef.current) {
            return;
        }
        seenMetadataRef.current = metadata;
        const familyKey = getClaudeFamilyKeyFromModelId(metadata?.currentAgentModel);
        if (familyKey && selectedModelKey && familyKey === selectedModelKey) {
            setConfirmed(true);
        }
    }, [metadata, selectedModelKey]);

    return confirmed;
}
