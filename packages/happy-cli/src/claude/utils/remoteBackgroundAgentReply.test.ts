/**
 * Regression: in remote mode, a main-chain reply that follows a message from a
 * background sub-agent (Agent tool with run_in_background) was never sent to
 * the server. The SDK→log converter chained the reply's parentUuid to the
 * sub-agent's last message, the protocol mapper inherited that sub-agent from
 * the parent, and — because the previous turn-end had cleared the sub-agent
 * mapping — buffered the reply forever. Seen 2026-11-07 in session
 * cmw6r9sf2012bs40udsmtpie6: the 20:08:41 reply has no envelope on the server.
 */
import { describe, expect, it } from 'vitest'
import { SDKToLogConverter } from './sdkToLogConverter'
import {
    closeClaudeTurnWithStatus,
    mapClaudeLogMessageToSessionEnvelopes,
    type ClaudeSessionProtocolState,
} from './sessionProtocolMapper'

describe('remote reply after a background sub-agent message', () => {
    it('keeps the main-chain parentUuid on the main chain', () => {
        const converter = new SDKToLogConverter({ sessionId: 's', cwd: '/p' })
        const main1 = converter.convert({
            type: 'assistant', parent_tool_use_id: null,
            message: { role: 'assistant', content: [{ type: 'text', text: 'one' }] },
        } as any)
        converter.convert({
            type: 'assistant', parent_tool_use_id: 'toolu_bg',
            message: { role: 'assistant', content: [{ type: 'text', text: 'sub' }] },
        } as any)
        const main2 = converter.convert({
            type: 'assistant', parent_tool_use_id: null,
            message: { role: 'assistant', content: [{ type: 'text', text: 'two' }] },
        } as any)
        expect(main2?.parentUuid).toBe(main1?.uuid)
        expect(main2?.isSidechain).toBe(false)
    })

    it('sends the reply to the server as main-chain text', () => {
        const converter = new SDKToLogConverter({ sessionId: 's', cwd: '/p' })
        const state: ClaudeSessionProtocolState = { currentTurnId: null }
        const send = (sdk: any) => {
            const log = converter.convert(sdk)
            if (!log) return []
            const mapped = mapClaudeLogMessageToSessionEnvelopes(log, state)
            state.currentTurnId = mapped.currentTurnId
            return mapped.envelopes
        }

        // Turn 1: start a background agent and finish the turn.
        send({
            type: 'assistant', parent_tool_use_id: null,
            message: { role: 'assistant', content: [{ type: 'tool_use', id: 'toolu_bg', name: 'Agent', input: { prompt: 'go', description: 'bg' } }] },
        })
        send({
            type: 'user', parent_tool_use_id: null,
            message: { role: 'user', content: [{ type: 'tool_result', tool_use_id: 'toolu_bg', content: 'Async agent launched' }] },
        })
        send({
            type: 'assistant', parent_tool_use_id: null,
            message: { role: 'assistant', content: [{ type: 'text', text: 'Started a worker.' }] },
        })
        const close = closeClaudeTurnWithStatus(state, 'completed')
        state.currentTurnId = close.currentTurnId

        // The background agent keeps working between turns.
        send({
            type: 'assistant', parent_tool_use_id: 'toolu_bg',
            message: { role: 'assistant', content: [{ type: 'tool_use', id: 'toolu_sub', name: 'Bash', input: { command: 'ls' } }] },
        })
        send({
            type: 'user', parent_tool_use_id: 'toolu_bg',
            message: { role: 'user', content: [{ type: 'tool_result', tool_use_id: 'toolu_sub', content: 'ok' }] },
        })

        // Turn 2: the main agent replies to the next prompt.
        const envelopes = send({
            type: 'assistant', parent_tool_use_id: null,
            message: { role: 'assistant', content: [{ type: 'text', text: 'Test reply: can you see this message in Happy?' }] },
        })

        const text = envelopes.find((e) => e.ev.t === 'text')
        expect(envelopes.some((e) => e.ev.t === 'turn-start')).toBe(true)
        expect(text).toBeDefined()
        expect((text as any).ev.text).toBe('Test reply: can you see this message in Happy?')
        expect(text?.subagent).toBeUndefined()
    })
})
