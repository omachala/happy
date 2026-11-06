import Foundation

/// storage.ts `currentViewingSessionId`: the chat on screen, which a
/// `session-event` never marks unread. Set when a chat appears and let go
/// of when it leaves the stack; read off the main thread by the sync engine.
public final class LegacyViewedSession: @unchecked Sendable {
    private let lock = NSLock()
    private var id: String?

    public init() {}

    /// The chat now on screen.
    public var current: String? { lock.withLock { id } }

    public func show(_ sessionId: String) {
        lock.withLock { id = sessionId }
    }

    /// Only the chat that is shown can hide itself, so a chat leaving after
    /// the next one appeared changes nothing.
    public func hide(_ sessionId: String) {
        lock.withLock { if id == sessionId { id = nil } }
    }
}
