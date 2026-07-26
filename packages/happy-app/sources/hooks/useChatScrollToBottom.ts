import * as React from 'react';

/**
 * Per-session "snap the chat to the bottom" channel.
 *
 * Why this exists: ChatList's inverted FlatList sticks to the visual bottom
 * only through `maintainVisibleContentPosition.autoscrollToTopThreshold`,
 * which follows new items only while the viewport is already within a few
 * pixels of the bottom. That is the right behaviour for agent output — it
 * stops a streaming reply from yanking the viewport while the user reads
 * older history — but it is wrong for the user's *own* message: sending
 * while scrolled up inserted the new bubble off-screen, so the message
 * looked lost even though it was in the store and on its way to the server.
 *
 * ChatList is rendered by SessionView but takes only a `session` prop, and
 * the send handler lives in SessionView. Rather than thread a ref through
 * the tree (ChatList -> ChatListInternal -> FlatList), the sender publishes
 * an intent here and the list subscribes. Keyed by sessionId so a request
 * never moves a different session's list.
 *
 * Deliberately fire-and-forget: if no list is mounted for that session the
 * request is dropped, because a list mounting later starts at the bottom
 * anyway.
 */

type Listener = () => void;

const listeners = new Map<string, Set<Listener>>();

/** Ask the chat list for `sessionId` to scroll to the newest message. */
export function requestChatScrollToBottom(sessionId: string) {
    const sessionListeners = listeners.get(sessionId);
    if (!sessionListeners) {
        return;
    }
    for (const listener of sessionListeners) {
        listener();
    }
}

/** Subscribe the mounted chat list to scroll-to-bottom requests. */
export function useChatScrollToBottomRequest(sessionId: string, handler: Listener) {
    // Keep the latest handler in a ref so re-subscribing isn't required when
    // the callback identity changes on re-render.
    const handlerRef = React.useRef(handler);
    handlerRef.current = handler;

    React.useEffect(() => {
        const listener: Listener = () => handlerRef.current();
        let sessionListeners = listeners.get(sessionId);
        if (!sessionListeners) {
            sessionListeners = new Set();
            listeners.set(sessionId, sessionListeners);
        }
        sessionListeners.add(listener);
        return () => {
            sessionListeners!.delete(listener);
            if (sessionListeners!.size === 0) {
                listeners.delete(sessionId);
            }
        };
    }, [sessionId]);
}
