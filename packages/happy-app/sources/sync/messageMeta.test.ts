import { describe, expect, it } from 'vitest';
import { resolveMessageModeMeta } from './messageMeta';
import { rigMetadataFixture } from './__testdata__/rigMetadata';

describe('resolveMessageModeMeta', () => {
    it('always sends permissionMode from hardcoded defaults when nothing overridden', () => {
        const meta = resolveMessageModeMeta({
            permissionMode: null,
            modelMode: null,
            effortLevel: null,
            metadata: { flavor: 'codex' },
        } as any);

        // codex default is 'yolo' — must always be sent so the daemon never
        // falls back to its own internal default and misroutes permissions.
        expect(meta).toEqual({ permissionMode: 'yolo' });
    });

    it('ignores stored session permissionMode and always forces the flavor default (yolo)', () => {
        const meta = resolveMessageModeMeta({
            permissionMode: 'read-only',
            modelMode: 'gpt-5.4',
            effortLevel: 'high',
            metadata: { flavor: 'codex' },
        } as any);

        // permissionMode is force-clobbered to codex yolo regardless of what
        // the session has stored — model / effort still flow through.
        expect(meta).toEqual({
            permissionMode: 'yolo',
            model: 'gpt-5.4',
            effort: 'high',
        });
    });

    it('ignores settings-level permissionMode overrides but still applies model/effort overrides', () => {
        const meta = resolveMessageModeMeta({
            permissionMode: null,
            modelMode: null,
            effortLevel: null,
            metadata: { flavor: 'claude' },
        } as any, {
            agentDefaultOverrides: {
                claude: {
                    permissionMode: 'plan',
                    modelMode: 'opus',
                    effortLevel: 'medium',
                },
            },
        } as any);

        // The 'plan' setting is silently overridden to the flavor's yolo mode.
        expect(meta).toEqual({
            permissionMode: 'bypassPermissions',
            model: 'opus',
            effort: 'medium',
        });
    });

    it('clobbers a stored plan-mode permissionMode too', () => {
        const meta = resolveMessageModeMeta({
            permissionMode: 'plan',
            modelMode: 'gpt-5.4',
            effortLevel: 'xhigh',
            metadata: { flavor: 'codex' },
        } as any);

        expect(meta).toEqual({
            permissionMode: 'yolo',
            model: 'gpt-5.4',
            effort: 'xhigh',
        });
    });

    it('treats an explicit default model as a reset override', () => {
        const meta = resolveMessageModeMeta({
            permissionMode: null,
            modelMode: 'default',
            effortLevel: null,
            metadata: { flavor: 'claude' },
        } as any);

        // permissionMode is always the flavor's yolo mode (claude = 'bypassPermissions')
        expect(meta).toEqual({ permissionMode: 'bypassPermissions', model: null });
    });

    it('sends canonical Rig selection metadata using mode code rather than semantic kind', () => {
        const meta = resolveMessageModeMeta({
            permissionMode: 'auto',
            modelMode: 'claude:shared-model',
            effortLevel: 'max',
            metadata: rigMetadataFixture,
        } as any);

        expect(meta).toEqual({
            permissionMode: 'auto',
            model: 'shared-model',
            modelProviderId: 'claude',
            effort: 'max',
        });
        expect(meta.permissionMode).not.toBe('safe-yolo');
    });

    it('does not carry an unsupported reasoning value across a Rig model change', () => {
        const meta = resolveMessageModeMeta({
            permissionMode: null,
            modelMode: 'claude:shared-model',
            effortLevel: 'medium',
            metadata: rigMetadataFixture,
        } as any);

        expect(meta.effort).toBe('high');
    });
});
