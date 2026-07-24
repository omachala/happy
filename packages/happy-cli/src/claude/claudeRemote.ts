import { EnhancedMode } from "./loop";
import { query, type CanCallToolOptions, type QueryOptions, type SDKMessage, type SDKSystemMessage, AbortError, SDKUserMessage } from '@/claude/sdk'
import type { MessageParam } from '@anthropic-ai/sdk/resources'
import { mapToClaudeMode } from "./utils/permissionMode";
import { claudeCheckSession } from "./utils/claudeCheckSession";
import { join } from 'node:path';
import { parseSpecialCommand } from "@/parsers/specialCommands";
import { logger } from "@/lib";
import { PushableAsyncIterable } from "@/utils/PushableAsyncIterable";
import { getProjectPath } from "./utils/path";
import { awaitFileExist } from "@/modules/watcher/awaitFileExist";
import { systemPrompt } from "./utils/systemPrompt";
import { PermissionResult } from "./sdk/types";
import type { JsRuntime } from "./runClaude";

export async function claudeRemote(opts: {

    // Fixed parameters
    sessionId: string | null,
    path: string,
    mcpServers?: Record<string, any>,
    claudeEnvVars?: Record<string, string>,
    claudeArgs?: string[],
    allowedTools: string[],
    signal?: AbortSignal,
    canCallTool: (toolName: string, input: unknown, mode: EnhancedMode, options: CanCallToolOptions) => Promise<PermissionResult>,
    /** Called when the Query object is ready — allows permission handler to call setPermissionMode */
    onQueryReady?: (query: { setPermissionMode: (mode: string) => Promise<void> }) => void,
    /** Path to temporary settings file with SessionStart hook (required for session tracking) */
    hookSettingsPath: string,
    /** JavaScript runtime to use for spawning Claude Code (default: 'node') */
    jsRuntime?: JsRuntime,

    // Dynamic parameters
    nextMessage: () => Promise<{ message: MessageParam['content'], mode: EnhancedMode } | null>,
    onReady: () => void,
    isAborted: (toolCallId: string) => boolean,

    // Callbacks
    onSessionFound: (id: string) => void,
    onThinkingChange?: (thinking: boolean) => void,
    onMessage: (message: SDKMessage) => void,
    onCompletionEvent?: (message: string) => void,
    onSessionReset?: () => void,
    onSDKMetadata?: (metadata: { tools?: string[]; slashCommands?: string[]; mcpServers?: { name: string; status: string }[]; skills?: string[] }) => void,
    /** Fires when the SDK first reports a running model, and again whenever the
     * observed model id changes (e.g. `/model` typed in a terminal attached to
     * the same Claude session). Enables the app UI to reflect the real model,
     * not just the user's picked mode. */
    onCurrentModelChange?: (model: string) => void
}) {

    // Check if session is valid
    let startFrom = opts.sessionId;
    if (opts.sessionId && !claudeCheckSession(opts.sessionId, opts.path)) {
        startFrom = null;
    }
    
    // Extract --resume from claudeArgs if present (for first spawn)
    if (!startFrom && opts.claudeArgs) {
        for (let i = 0; i < opts.claudeArgs.length; i++) {
            if (opts.claudeArgs[i] === '--resume') {
                // Check if next arg exists and looks like a session ID
                if (i + 1 < opts.claudeArgs.length) {
                    const nextArg = opts.claudeArgs[i + 1];
                    // If next arg doesn't start with dash and contains dashes, it's likely a UUID
                    if (!nextArg.startsWith('-') && nextArg.includes('-')) {
                        startFrom = nextArg;
                        logger.debug(`[claudeRemote] Found --resume with session ID: ${startFrom}`);
                        break;
                    } else {
                        // Just --resume without UUID - SDK doesn't support this
                        logger.debug('[claudeRemote] Found --resume without session ID - not supported in remote mode');
                        break;
                    }
                } else {
                    // --resume at end of args - SDK doesn't support this
                    logger.debug('[claudeRemote] Found --resume without session ID - not supported in remote mode');
                    break;
                }
            }
        }
    }

    // Set environment variables for Claude Code SDK
    if (opts.claudeEnvVars) {
        Object.entries(opts.claudeEnvVars).forEach(([key, value]) => {
            process.env[key] = value;
        });
    }

    // Get initial message
    const initial = await opts.nextMessage();
    if (!initial) { // No initial message - exit
        return;
    }

    // Handle special commands (extract text for parsing when content is a block array)
    const initialText = typeof initial.message === 'string'
        ? initial.message
        : (initial.message.find((b) => b.type === 'text') as { type: 'text'; text: string } | undefined)?.text ?? '';
    const specialCommand = parseSpecialCommand(initialText);

    // Handle /clear command
    if (specialCommand.type === 'clear') {
        if (opts.onCompletionEvent) {
            opts.onCompletionEvent('Context was reset');
        }
        if (opts.onSessionReset) {
            opts.onSessionReset();
        }
        opts.onReady();
        return;
    }

    // Handle /compact command
    let isCompactCommand = false;
    if (specialCommand.type === 'compact') {
        logger.debug('[claudeRemote] /compact command detected - will process as normal but with compaction behavior');
        isCompactCommand = true;
        if (opts.onCompletionEvent) {
            opts.onCompletionEvent('Compaction started');
        }
    }

    // Prepare SDK options
    let mode = initial.mode;
    const sdkOptions: QueryOptions = {
        cwd: opts.path,
        resume: startFrom ?? undefined,
        mcpServers: opts.mcpServers,
        permissionMode: mapToClaudeMode(initial.mode.permissionMode),
        model: initial.mode.model,
        fallbackModel: initial.mode.fallbackModel,
        customSystemPrompt: initial.mode.customSystemPrompt ? initial.mode.customSystemPrompt + '\n\n' + systemPrompt : undefined,
        appendSystemPrompt: initial.mode.appendSystemPrompt ? initial.mode.appendSystemPrompt + '\n\n' + systemPrompt : systemPrompt,
        allowedTools: initial.mode.allowedTools ? initial.mode.allowedTools.concat(opts.allowedTools) : opts.allowedTools,
        disallowedTools: initial.mode.disallowedTools,
        effort: initial.mode.effort,
        canCallTool: (toolName: string, input: unknown, options: CanCallToolOptions) => opts.canCallTool(toolName, input, mode, options),
        abort: opts.signal,
        settingsPath: opts.hookSettingsPath,
    }

    // Track thinking state
    let thinking = false;
    const updateThinking = (newThinking: boolean) => {
        if (thinking !== newThinking) {
            thinking = newThinking;
            logger.debug(`[claudeRemote] Thinking state changed to: ${thinking}`);
            if (opts.onThinkingChange) {
                opts.onThinkingChange(thinking);
            }
        }
    };

    // Push initial message
    let messages = new PushableAsyncIterable<SDKUserMessage>();
    messages.push({
        type: 'user',
        parent_tool_use_id: null,
        message: {
            role: 'user',
            content: initial.message,
        },
    });

    // Start the loop
    const response = query({
        prompt: messages,
        options: sdkOptions,
    });

    // Expose query control methods to permission handler
    if (opts.onQueryReady) {
        opts.onQueryReady({
            setPermissionMode: (mode: string) => response.setPermissionMode(mode as any),
        });
    }

    updateThinking(true);

    // Continuously pull queued follow-up messages and stream them straight
    // into the live SDK input as soon as they're available, instead of
    // waiting for the current turn's `result` event. This lets a message
    // typed while Claude is still working reach it immediately, the same
    // way typing ahead in an interactive terminal session behaves.
    //
    // `opts.nextMessage()` returns null both when the session is ending and
    // when the queued message's mode (permission mode/model/effort) differs
    // from the current turn's — in the latter case a fresh `claudeRemote`
    // call is required to apply it, so the live stream must only be closed
    // once the in-flight turn actually finishes (`thinking` is false).
    // Otherwise we'd truncate a turn that's still running.
    let messagesEnded = false;
    let endMessagesOnceIdle = false;
    const endMessages = () => {
        if (!messagesEnded) {
            messagesEnded = true;
            messages.end();
        }
    };
    const pumpNextMessage = (): void => {
        opts.nextMessage().then((next) => {
            if (!next) {
                endMessagesOnceIdle = true;
                if (!thinking) {
                    endMessages();
                }
                return;
            }
            mode = next.mode;
            messages.push({ type: 'user', parent_tool_use_id: null, message: { role: 'user', content: next.message } });
            pumpNextMessage();
        }).catch(() => {
            endMessagesOnceIdle = true;
            if (!thinking) {
                endMessages();
            }
        });
    };
    pumpNextMessage();

    // Track the last raw model id we surfaced upstream so the callback
    // fires only on genuine changes (init and every out-of-band /model
    // switch), not once per assistant chunk.
    let lastReportedModel: string | null = null;
    const reportModel = (candidate: string | null | undefined) => {
        if (!candidate || candidate === lastReportedModel) return;
        lastReportedModel = candidate;
        opts.onCurrentModelChange?.(candidate);
    };

    try {
        logger.debug(`[claudeRemote] Starting to iterate over response`);

        for await (const message of response) {
            logger.debugLargeJson(`[claudeRemote] Message ${message.type}`, message);

            // Handle messages. During /compact, Claude emits the generated
            // summary as a normal assistant text message before the result.
            // Mark it so downstream UI/protocol mapping can treat it as
            // housekeeping instead of a real assistant response.
            const outboundMessage = isCompactCommand && message.type === 'assistant'
                ? { ...message, isCompactSummary: true } as SDKMessage
                : message;
            opts.onMessage(outboundMessage);

            // Every assistant reply carries the model it was generated with —
            // pick out changes so a `/model` switch typed directly at the
            // Claude CLI (bypassing the app) still propagates back to the UI.
            if (message.type === 'assistant') {
                reportModel(message.message.model);
            }

            // Handle special system messages
            if (message.type === 'system' && message.subtype === 'init') {
                // Start thinking when session initializes
                updateThinking(true);

                const systemInit = message as SDKSystemMessage;

                reportModel(systemInit.model);

                // Session id is still in memory, wait until session file is written to disk
                // Start a watcher for to detect the session id
                // Emit SDK metadata (tools, slash commands) from init message
                if (opts.onSDKMetadata) {
                    opts.onSDKMetadata({
                        tools: systemInit.tools,
                        slashCommands: systemInit.slash_commands,
                        mcpServers: systemInit.mcp_servers?.map(s => ({ name: s.name, status: s.status })),
                        skills: systemInit.skills,
                    });
                }

                // Session id is still in memory, wait until session file is written to disk
                // Start a watcher for to detect the session id
                if (systemInit.session_id) {
                    logger.debug(`[claudeRemote] Waiting for session file to be written to disk: ${systemInit.session_id}`);
                    const projectDir = getProjectPath(opts.path);
                    const found = await awaitFileExist(join(projectDir, `${systemInit.session_id}.jsonl`), 30000);
                    logger.debug(`[claudeRemote] Session file found: ${systemInit.session_id} ${found}`);
                    if (!found) {
                        // The transcript never landed on disk within the grace
                        // window. We still register the id so the (now
                        // bounded) scanner watcher can pick it up if it shows
                        // up late and otherwise drops it cleanly instead of
                        // wedging — but surface the anomaly so a stuck remote
                        // launch is visible in the app rather than a silent
                        // "dead instance".
                        logger.debug(`[claudeRemote] WARNING: session transcript ${systemInit.session_id} never appeared after 30s`);
                        opts.onCompletionEvent?.('⚠️ Claude session did not produce a transcript — the agent may be unresponsive. Try sending your message again.');
                    }
                    opts.onSessionFound(systemInit.session_id);
                }
            }

            // Handle result messages
            if (message.type === 'result') {
                updateThinking(false);
                logger.debug('[claudeRemote] Result received');

                // Send completion messages
                if (isCompactCommand) {
                    logger.debug('[claudeRemote] Compaction completed');
                    if (opts.onCompletionEvent) {
                        opts.onCompletionEvent('Compaction completed');
                    }
                    isCompactCommand = false;
                }

                // Send ready event
                opts.onReady();

                // Re-emit the current model on every turn boundary, bypassing
                // the dedupe. The app uses each fresh metadata push as its
                // "server-confirmed" signal to flip the model chip from gray
                // to green, so we need at least one write per completed turn
                // even when the model didn't change.
                if (lastReportedModel !== null) {
                    opts.onCurrentModelChange?.(lastReportedModel);
                }

                // Follow-up messages are streamed in continuously by
                // `pumpNextMessage` above. If it already discovered there's
                // nothing more to send for this turn's mode (session end or
                // a pending mode change), it deferred closing the live
                // stream until now — the turn just finished, so it's safe.
                if (endMessagesOnceIdle) {
                    endMessages();
                }
            }

            // Handle tool result
            if (message.type === 'user') {
                const msg = message as SDKUserMessage;
                if (msg.message.role === 'user' && Array.isArray(msg.message.content)) {
                    for (let c of msg.message.content) {
                        if (c.type === 'tool_result' && c.tool_use_id && opts.isAborted(c.tool_use_id)) {
                            logger.debug('[claudeRemote] Tool aborted, exiting claudeRemote');
                            return;
                        }
                    }
                }
            }
        }
    } catch (e) {
        if (e instanceof AbortError) {
            logger.debug(`[claudeRemote] Aborted`);
            // Ignore
        } else {
            throw e;
        }
    } finally {
        updateThinking(false);
    }
}
