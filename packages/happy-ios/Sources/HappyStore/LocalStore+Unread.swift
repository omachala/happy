import Foundation
import GRDB
import HappyWire

/// A session that moved past where the person last read it, found by
/// `LocalStore.unreadCandidates`. `newestFromUser` says whether the
/// newest message is the person's own (`LocalStore.isUserSide`) when it is
/// stored here, nil when it has to be asked for.
public struct UnreadCandidate: Equatable, Sendable {
    public var id: String
    public var seq: Int
    public var newestFromUser: Bool?

    public init(id: String, seq: Int, newestFromUser: Bool?) {
        self.id = id
        self.seq = seq
        self.newestFromUser = newestFromUser
    }
}

extension LocalStore {
    /// sync.ts `session-event` → storage.ts `markSessionUnread`: the server
    /// says this one session finished a turn, wants a permission or asks
    /// something. The caller has already left out the chat on screen.
    /// Lasts until the chat is read (`markSessionRead`), across launches.
    public func markSessionUnread(id: String) throws {
        try performWrite { db in
            try db.execute(sql: "UPDATE session SET unread = 1 WHERE id = ? AND unread = 0", arguments: [id])
        }
    }

    /// The person has seen the session as it is now: clears unread and
    /// moves its read marker to the newest message (`sessionRead`), so what
    /// was read inside the chat never comes back as unread. Called when the
    /// chat is opened and when it is left.
    public func markSessionRead(id: String, at readAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) throws {
        try performWrite { db in
            try db.execute(sql: "UPDATE session SET unread = 0 WHERE id = ? AND unread = 1", arguments: [id])
            try db.execute(sql: """
                INSERT INTO sessionRead (sessionId, seq, readAt)
                SELECT id, seq, ? FROM session WHERE id = ?
                ON CONFLICT(sessionId) DO UPDATE SET seq = max(seq, excluded.seq), readAt = max(readAt, excluded.readAt)
                """, arguments: [readAt, id])
        }
    }

    /// The person's own message is the newest: read by definition. Moves
    /// the marker without touching `readAt` (the person did not open it).
    public func advanceReadMarker(id: String, through seq: Int) throws {
        try performWrite { db in
            try db.execute(sql: """
                INSERT INTO sessionRead (sessionId, seq, readAt) VALUES (?, ?, 0)
                ON CONFLICT(sessionId) DO UPDATE SET seq = max(seq, excluded.seq)
                """, arguments: [id, seq])
        }
    }

    /// A missed turn, recovered by a sync: marks the session unread only
    /// while it is still past its read marker at `seq` (the chat was not
    /// opened since the candidate was found). Returns whether it marked.
    @discardableResult
    public func markSessionUnread(id: String, through seq: Int) throws -> Bool {
        try performWrite { db in
            let read = try Int.fetchOne(db, sql: "SELECT seq FROM sessionRead WHERE sessionId = ?", arguments: [id]) ?? 0
            guard read < seq else { return false }
            try db.execute(sql: "UPDATE session SET unread = 1 WHERE id = ? AND unread = 0", arguments: [id])
            return db.changesCount > 0
        }
    }

    /// Each chat's latest activity (ms): the later of its newest message,
    /// either side, and when the person last opened or left it. Home orders
    /// the fork's sessions by it and calls one stale past a day.
    static func fetchActivity(_ db: Database) throws -> [String: Int64] {
        var result: [String: Int64] = [:]
        // A cache read before its migrations (the migration tests) has none.
        guard try db.tableExists("sessionRead") else { return result }
        for row in try Row.fetchAll(db, sql: "SELECT sessionId, max(readAt, messageAt) AS at FROM sessionRead WHERE readAt > 0 OR messageAt > 0") {
            result[row["sessionId"]] = row["at"]
        }
        return result
    }

    /// How far a newer message must be before it is written down: home
    /// orders to the minute, so a streaming turn writes once a minute,
    /// not once a message, and its row does not shuffle meanwhile.
    static let messageAtGranularityMs: Int64 = 60_000

    /// A message, either side, at `at`: the chat's activity, to the minute.
    static func noteMessageAt(_ sessionId: String, _ at: Int64, _ db: Database) throws {
        try db.execute(sql: """
            INSERT INTO sessionRead (sessionId, seq, readAt, messageAt) VALUES (?, 0, 0, ?)
            ON CONFLICT(sessionId) DO UPDATE SET messageAt = excluded.messageAt
            WHERE excluded.messageAt >= sessionRead.messageAt + ?
            """, arguments: [sessionId, at, messageAtGranularityMs])
    }

    /// The newest message a sync asked for alone (`recoverUnread`).
    public func noteSessionMessage(id: String, at: Int64) throws {
        try performWrite { db in
            guard try SessionRecord.exists(db, key: id) else { return }
            try Self.noteMessageAt(id, at, db)
        }
    }

    /// Sessions whose newest message is past where the person last read
    /// them and that are not unread yet: what a turn finished while the app
    /// was suspended, killed or offline leaves behind. Leaves out `viewing`
    /// (the chat on screen), sessions archived or being archived, sessions
    /// that cannot be opened, and one still working on its turn by a fresh
    /// `thinking` (it is flagged once it settles; a stale flag from before a
    /// suspension does not hold it back).
    public func unreadCandidates(excluding viewing: String?, now: Int64, freshThinkingMs: Int64 = 60_000) throws -> [UnreadCandidate] {
        try performRead { db in
            let rows = try SessionRecord.fetchAll(db, sql: """
                SELECT s.* FROM session s LEFT JOIN sessionRead r ON r.sessionId = s.id
                WHERE s.unread = 0 AND s.archiving = 0 AND s.decryptable = 1 AND s.seq > coalesce(r.seq, 0)
                ORDER BY s.updatedAt DESC
                """)
            return try rows.compactMap { session in
                guard session.id != viewing, !session.isArchivedOnServer else { return nil }
                if session.thinking, now - session.thinkingAt < freshThinkingMs,
                   !session.hasPendingPermissionRequests { return nil }
                let newest = try MessageRecord
                    .filter(Column("sessionId") == session.id && Column("seq") == session.seq)
                    .fetchOne(db)
                return UnreadCandidate(id: session.id, seq: session.seq, newestFromUser: newest.map { Self.isUserSide($0.content) })
            }
        }
    }

    /// The person's side of the chat: their text (`role: user`), a session
    /// envelope they wrote (typed in the terminal), or the daemon's receipt
    /// for one. Anything else, including what cannot be opened, is the
    /// agent's.
    public static func isUserSide(_ content: JSONValue?) -> Bool {
        guard let content else { return false }
        switch content["role"]?.stringValue {
        case "user":
            return true
        case "session":
            let body = content["content"] ?? .null
            let envelope = body["type"]?.stringValue == "session" ? body["data"] ?? .null : body
            if envelope["role"]?.stringValue == "user" { return true }
            return Self.receipts.contains(envelope["ev"]?["t"]?.stringValue ?? "")
        case "agent":
            return Self.receipts.contains(content["content"]?["data"]?["type"]?.stringValue ?? "")
        default:
            return false
        }
    }

    private static let receipts: Set<String> = ["user-message-accepted", "user-message-rejected"]

    /// A session first seen after the account's first sync has no marker:
    /// it counts from zero, so one started elsewhere that ran a turn shows.
    /// On the first sync every session is seeded where it is, so a fresh
    /// install or a new account does not light up the whole list.
    static func seedReadMarker(_ session: SessionRecord, _ db: Database) throws {
        guard !(try SyncStateRecord.exists(db, key: SyncCursor.sessionsChangedSince.rawValue)) else { return }
        try db.execute(sql: "INSERT OR IGNORE INTO sessionRead (sessionId, seq, readAt) VALUES (?, ?, 0)",
                       arguments: [session.id, session.seq])
    }
}
