import Foundation
import GRDB
import XCTest
@testable import HappyStore
import HappyWire

/// The per-session read marker (`sessionRead`) and the candidates a sync
/// marks unread when a turn ended while nobody was looking.
final class SessionReadMarkerTests: XCTestCase {
    var store: LocalStore!

    override func setUpWithError() throws {
        store = try LocalStore.inMemory()
    }

    private func agent(_ sessionId: String, seq: Int) -> MessageRecord {
        MessageRecord(id: "\(sessionId)-\(seq)", sessionId: sessionId, seq: seq, localId: nil, createdAt: Int64(seq), updatedAt: Int64(seq),
                      contentCipher: "c", content: .object([
                          "role": .string("session"),
                          "content": .object(["role": .string("agent"), "ev": .object(["t": .string("text"), "text": .string("done")])]),
                      ]))
    }

    private func user(_ sessionId: String, seq: Int) -> MessageRecord {
        MessageRecord(id: "\(sessionId)-\(seq)", sessionId: sessionId, seq: seq, localId: nil, createdAt: Int64(seq), updatedAt: Int64(seq),
                      contentCipher: "c", content: .object([
                          "role": .string("user"), "content": .object(["type": .string("text"), "text": .string("hi")]),
                      ]))
    }

    private func synced() throws {
        try store.applySessionListBatch([], checkpoint: SessionListCheckpoint(changedSince: 1, fullIDs: nil, completedAt: nil))
    }

    func testTheFirstSyncSeedsMarkersSoNothingLightsUp() throws {
        try store.upsertSessions([makeSession("a", seq: 5), makeSession("b", seq: 9)])
        XCTAssertEqual(try store.unreadCandidates(excluding: nil, now: 0), [])
    }

    func testASessionThatMovedPastItsMarkerIsACandidate() throws {
        try store.upsertSessions([makeSession("a", seq: 5, updatedAt: 100)])
        try synced()
        try store.upsertSessions([makeSession("a", seq: 7, updatedAt: 200)])
        XCTAssertEqual(try store.unreadCandidates(excluding: nil, now: 0), [UnreadCandidate(id: "a", seq: 7, readSeq: 5, newestSaid: nil)])
        XCTAssertEqual(try store.unreadCandidates(excluding: "a", now: 0), [], "the chat on screen is read")

        _ = try store.applyLiveMessage(agent("a", seq: 7))
        XCTAssertEqual(try store.unreadCandidates(excluding: nil, now: 0).first?.newestSaid, .agent)
        _ = try store.applyLiveMessage(user("a", seq: 8))
        XCTAssertEqual(try store.unreadCandidates(excluding: nil, now: 0).first?.newestSaid, .user)
    }

    func testASessionFirstSeenAfterTheFirstSyncCountsFromZero() throws {
        try synced()
        try store.upsertSessions([makeSession("new", seq: 3)])
        XCTAssertEqual(try store.unreadCandidates(excluding: nil, now: 0).map(\.id), ["new"])
    }

    func testReadingMovesTheMarkerAndClearsUnread() throws {
        try store.upsertSessions([makeSession("a", seq: 5)])
        try synced()
        try store.upsertSessions([makeSession("a", seq: 7, updatedAt: 200)])
        XCTAssertTrue(try store.markSessionUnread(id: "a", through: 7))
        XCTAssertTrue(try XCTUnwrap(store.session(id: "a")).unread)

        try store.markSessionRead(id: "a", at: 5_000)
        XCTAssertFalse(try XCTUnwrap(store.session(id: "a")).unread)
        XCTAssertEqual(try store.unreadCandidates(excluding: nil, now: 0), [])
        XCTAssertEqual(try store.homeSnapshot().activity, ["a": 5_000])
        XCTAssertFalse(try store.markSessionUnread(id: "a", through: 7), "read since the candidate was found")
    }

    func testTheOwnMessageMovesTheMarkerOnly() throws {
        try store.upsertSessions([makeSession("a", seq: 5)])
        try synced()
        try store.upsertSessions([makeSession("a", seq: 6, updatedAt: 200)])
        try store.advanceReadMarker(id: "a", through: 6)
        XCTAssertEqual(try store.unreadCandidates(excluding: nil, now: 0), [])
        XCTAssertFalse(try XCTUnwrap(store.session(id: "a")).unread)
        XCTAssertEqual(try store.homeSnapshot().activity, [:], "not opened")
    }

    func testAFreshlyThinkingSessionWaitsForItsTurnToEnd() throws {
        try store.upsertSessions([makeSession("a", seq: 5)])
        try synced()
        try store.upsertSessions([makeSession("a", seq: 6, updatedAt: 200)])
        try store.applySessionActivity(id: "a", active: true, activeAt: 10_000, thinking: true)
        XCTAssertEqual(try store.unreadCandidates(excluding: nil, now: 20_000), [])
        XCTAssertEqual(try store.unreadCandidates(excluding: nil, now: 200_000).map(\.id), ["a"], "a stale flag from before a suspension")
    }

    func testUnreadAndMarkersSurviveARelaunch() throws {
        let queue = try DatabaseQueue()
        let first = try LocalStore(writer: queue)
        try first.upsertSessions([makeSession("a", seq: 5)])
        try first.applySessionListBatch([], checkpoint: SessionListCheckpoint(changedSince: 1, fullIDs: nil, completedAt: nil))
        try first.upsertSessions([makeSession("a", seq: 7, updatedAt: 200)])
        try first.markSessionUnread(id: "a", through: 7)

        let reopened = try LocalStore(writer: queue)
        XCTAssertTrue(try XCTUnwrap(reopened.session(id: "a")).unread)
        try reopened.markSessionRead(id: "a")
        XCTAssertEqual(try LocalStore(writer: queue).unreadCandidates(excluding: nil, now: 0), [])
    }

    /// An upgrade from a build without markers seeds them from what is
    /// stored, so the existing list does not all light up.
    func testTheUpgradeSeedsMarkersFromTheStoredSessions() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue, upTo: "v8-intents")
        try queue.write { db in
            try makeSession("old", seq: 40).insert(db)
            try SyncStateRecord(key: SyncCursor.sessionsChangedSince.rawValue, value: 1).insert(db)
        }
        let upgraded = try LocalStore(writer: queue)
        XCTAssertEqual(try upgraded.unreadCandidates(excluding: nil, now: 0), [])
        try upgraded.upsertSessions([makeSession("old", seq: 41, updatedAt: 200)])
        XCTAssertEqual(try upgraded.unreadCandidates(excluding: nil, now: 0).map(\.id), ["old"], "a turn after the upgrade still counts")
    }

    /// Home's order: the newest message to the minute, or the last open.
    func testActivityIsTheNewestMessageToTheMinuteOrTheLastRead() throws {
        try store.upsertSessions([makeSession("a", seq: 0)])
        XCTAssertEqual(try store.homeSnapshot().activity, [:])
        _ = try store.applyLiveMessage(agent("a", seq: 1).at(100_000))
        XCTAssertEqual(try store.homeSnapshot().activity, ["a": 100_000])
        _ = try store.applyLiveMessage(agent("a", seq: 2).at(130_000))
        XCTAssertEqual(try store.homeSnapshot().activity, ["a": 100_000], "a streaming turn writes once a minute")
        _ = try store.applyLiveMessage(user("a", seq: 3).at(161_000))
        XCTAssertEqual(try store.homeSnapshot().activity, ["a": 161_000], "either side")
        try store.markSessionRead(id: "a", at: 500_000)
        XCTAssertEqual(try store.homeSnapshot().activity, ["a": 500_000])
    }

    func testTheUpgradeSeedsActivityFromTheNewestStoredMessage() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue, upTo: "v9-session-read")
        try queue.write { db in
            try makeSession("old", seq: 2).insert(db)
            try db.execute(sql: "INSERT INTO sessionRead (sessionId, seq, readAt) VALUES ('old', 2, 0)")
            try agent("old", seq: 1).at(7_000).insert(db)
            try agent("old", seq: 2).at(9_000).insert(db)
        }
        XCTAssertEqual(try LocalStore(writer: queue).homeSnapshot().activity, ["old": 9_000])
    }

    private func turnEnd(_ sessionId: String, seq: Int) -> MessageRecord {
        MessageRecord(id: "\(sessionId)-\(seq)", sessionId: sessionId, seq: seq, localId: nil, createdAt: Int64(seq), updatedAt: Int64(seq),
                      contentCipher: "c", content: .object([
                          "role": .string("session"),
                          "content": .object(["role": .string("agent"), "ev": .object(["t": .string("turn-end"), "status": .string("completed")])]),
                      ]))
    }

    private func event(_ sessionId: String, seq: Int, _ type: String) -> MessageRecord {
        MessageRecord(id: "\(sessionId)-\(seq)", sessionId: sessionId, seq: seq, localId: nil, createdAt: Int64(seq), updatedAt: Int64(seq),
                      contentCipher: "c", content: .object([
                          "role": .string("agent"),
                          "content": .object(["type": .string("event"), "data": .object(["type": .string(type)])]),
                      ]))
    }

    /// A turn ends with housekeeping (turn-end, ready) after the agent's
    /// words: what counts is the newest thing actually said.
    func testHousekeepingIsNotSomethingSaid() throws {
        try store.upsertSessions([makeSession("a", seq: 5), makeSession("b", seq: 5), makeSession("c", seq: 5)])
        try synced()
        try store.upsertSessions([makeSession("a", seq: 7, updatedAt: 200), makeSession("b", seq: 7, updatedAt: 200),
                                  makeSession("c", seq: 7, updatedAt: 200)])
        _ = try store.applyLiveMessage(agent("a", seq: 6))
        _ = try store.applyLiveMessage(turnEnd("a", seq: 7))
        _ = try store.applyLiveMessage(user("b", seq: 6))
        _ = try store.applyLiveMessage(event("b", seq: 7, "ready"))
        _ = try store.applyLiveMessage(event("c", seq: 6, "switch"))
        _ = try store.applyLiveMessage(turnEnd("c", seq: 7))
        let said = Dictionary(uniqueKeysWithValues: try store.unreadCandidates(excluding: nil, now: 0).map { ($0.id, $0.newestSaid) })
        XCTAssertEqual(said["a"], .agent, "the agent's answer before its turn-end")
        XCTAssertEqual(said["b"], .user, "the person's own message before a ready")
        XCTAssertEqual(said["c"], .housekeeping, "a mode switch and a turn-end: nothing new to read")
    }

    func testOnlyHousekeepingButOlderMissingIsAskedFor() throws {
        try store.upsertSessions([makeSession("a", seq: 5)])
        try synced()
        try store.upsertSessions([makeSession("a", seq: 7, updatedAt: 200)])
        _ = try store.applyLiveMessage(turnEnd("a", seq: 7))
        XCTAssertEqual(try store.unreadCandidates(excluding: nil, now: 0).first?.newestSaid, nil)
    }

    func testTheSideOfAMessage() {
        func session(_ ev: [String: JSONValue]) -> JSONValue {
            .object(["role": .string("session"), "content": .object(["role": .string("agent"), "ev": .object(ev)])])
        }
        func agentEvent(_ type: String) -> JSONValue {
            .object(["role": .string("agent"), "content": .object(["type": .string("event"), "data": .object(["type": .string(type)])])])
        }
        func acp(_ type: String) -> JSONValue {
            .object(["role": .string("agent"), "content": .object(["type": .string("acp"), "provider": .string("gemini"), "data": .object(["type": .string(type)])])])
        }
        XCTAssertEqual(LocalStore.side(.object(["role": .string("user")])), .user)
        XCTAssertEqual(LocalStore.side(session(["t": .string("text"), "text": .string("done")])), .agent)
        XCTAssertEqual(LocalStore.side(session(["t": .string("tool-call-start"), "call": .string("1")])), .agent)
        XCTAssertEqual(LocalStore.side(session(["t": .string("service"), "text": .string("")])), .housekeeping, "usage only")
        for t in ["turn-start", "turn-end", "start", "stop"] {
            XCTAssertEqual(LocalStore.side(session(["t": .string(t)])), .housekeeping, t)
        }
        for type in ["ready", "switch", "message", "limit-reached"] {
            XCTAssertEqual(LocalStore.side(agentEvent(type)), .housekeeping, type)
        }
        XCTAssertEqual(LocalStore.side(agentEvent("user-message-accepted")), .user)
        XCTAssertEqual(LocalStore.side(acp("message")), .agent)
        XCTAssertEqual(LocalStore.side(acp("permission-request")), .agent)
        for type in ["task_started", "task_complete", "turn_aborted", "token_count"] {
            XCTAssertEqual(LocalStore.side(acp(type)), .housekeeping, type)
        }
        XCTAssertEqual(LocalStore.side(nil), .agent, "sealed: a message all the same")
    }

    func testTheUserSideOfTheChat() {
        XCTAssertTrue(LocalStore.isUserSide(.object(["role": .string("user")])))
        XCTAssertTrue(LocalStore.isUserSide(.object(["role": .string("session"), "content": .object(["role": .string("user"), "ev": .object(["t": .string("text")])])])))
        XCTAssertTrue(LocalStore.isUserSide(.object(["role": .string("session"), "content": .object(["role": .string("agent"), "ev": .object(["t": .string("user-message-accepted")])])])))
        XCTAssertFalse(LocalStore.isUserSide(.object(["role": .string("session"), "content": .object(["role": .string("agent"), "ev": .object(["t": .string("turn-end")])])])))
        XCTAssertFalse(LocalStore.isUserSide(.object(["role": .string("agent"), "content": .object(["type": .string("event"), "data": .object(["type": .string("ready")])])])))
        XCTAssertFalse(LocalStore.isUserSide(nil))
    }
}

private extension MessageRecord {
    func at(_ createdAt: Int64) -> MessageRecord {
        var copy = self
        copy.createdAt = createdAt
        return copy
    }
}
