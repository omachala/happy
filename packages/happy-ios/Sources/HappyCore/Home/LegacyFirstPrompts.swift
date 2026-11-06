import Foundation
import GRDB
import HappyStore

/// The fork's fallback chat titles (sessionUtils.ts `getSessionName`): a
/// chat the agent never named (`metadata.summary`) is called by its first
/// prompt, the earliest stored user text (`displayText` before `text`),
/// made a title by `LegacyMachineHome.title(fromText:)`.
///
/// Only live chats without a summary are looked at, and only their first
/// messages, so the read stays small. It runs on its own observation queue
/// when a session's metadata or message cursors move (`seq`, `syncedMessageSeq`), never on the
/// main thread, and hands on a value only when a title changed. The
/// earliest message never changes once stored, so a found title stays.
///
/// The fork's third fallback, the server's `lastMessage`, is not here:
/// `/v2/sessions` carries no such field, and the fork's server sends
/// `lastMessage: null` on `/v1/sessions` too.
public enum LegacyFirstPrompts {
    /// How many of a chat's first messages are read for its first prompt.
    static let scanLimit = 50

    private static let queue = DispatchQueue(label: "HappyCore.firstPrompts", qos: .utility)

    /// Session id to title, now and on every change, until the stream's
    /// consumer stops.
    public static func snapshots(_ store: LocalStore) -> AsyncStream<[String: String]> {
        let writer = store.writer
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let region = SQLRequest<Row>(sql: "SELECT id, active, archiving, metadata, seq, syncedMessageSeq FROM session")
            let cancellable = ValueObservation
                .tracking(region: region, fetch: { db in try fetch(db) })
                .removeDuplicates()
                .start(
                    in: writer,
                    scheduling: .async(onQueue: queue),
                    onError: { _ in continuation.finish() },
                    onChange: { continuation.yield($0) }
                )
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    /// The titles as stored now.
    public static func fetch(_ db: Database) throws -> [String: String] {
        let untitled = try String.fetchAll(db, sql: """
            SELECT id FROM session
            WHERE active = 1 AND archiving = 0
              AND COALESCE(TRIM(json_extract(metadata, '$.summary.text')), '') = ''
            """)
        var titles: [String: String] = [:]
        for id in untitled {
            let messages = try MessageRecord
                .filter(Column("sessionId") == id)
                .order(Column("createdAt"), Column("seq"))
                .limit(scanLimit)
                .fetchAll(db)
            if let title = firstPrompt(messages) { titles[id] = title }
        }
        return titles
    }

    /// storage.ts `applyMessages`: the earliest user text among `messages`,
    /// as a title; nil when there is none or it is blank.
    static func firstPrompt(_ messages: [MessageRecord]) -> String? {
        var earliest: (at: Int64, text: String)?
        for message in messages {
            guard let record = ChatNormalizer.normalize(message), case .user(let text) = record.body else { continue }
            let shown = record.meta?.displayText ?? text
            if earliest.map({ record.createdAt < $0.at }) ?? true {
                earliest = (record.createdAt, shown)
            }
        }
        guard let earliest else { return nil }
        let title = LegacyMachineHome.title(fromText: earliest.text)
        return title.isEmpty ? nil : title
    }
}
