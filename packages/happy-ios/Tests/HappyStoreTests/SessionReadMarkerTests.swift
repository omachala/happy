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
        XCTAssertEqual(try store.unreadCandidates(excluding: nil, now: 0), [UnreadCandidate(id: "a", seq: 7, newestFromUser: nil)])
        XCTAssertEqual(try store.unreadCandidates(excluding: "a", now: 0), [], "the chat on screen is read")

        _ = try store.applyLiveMessage(agent("a", seq: 7))
        XCTAssertEqual(try store.unreadCandidates(excluding: nil, now: 0).first?.newestFromUser, false)
        _ = try store.applyLiveMessage(user("a", seq: 8))
        XCTAssertEqual(try store.unreadCandidates(excluding: nil, now: 0).first?.newestFromUser, true)
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
        XCTAssertEqual(try store.sessionReadTimes(), ["a": 5_000])
        XCTAssertFalse(try store.markSessionUnread(id: "a", through: 7), "read since the candidate was found")
    }

    func testTheOwnMessageMovesTheMarkerOnly() throws {
        try store.upsertSessions([makeSession("a", seq: 5)])
        try synced()
        try store.upsertSessions([makeSession("a", seq: 6, updatedAt: 200)])
        try store.advanceReadMarker(id: "a", through: 6)
        XCTAssertEqual(try store.unreadCandidates(excluding: nil, now: 0), [])
        XCTAssertFalse(try XCTUnwrap(store.session(id: "a")).unread)
        XCTAssertEqual(try store.sessionReadTimes(), [:], "not opened")
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

    func testTheUserSideOfTheChat() {
        XCTAssertTrue(LocalStore.isUserSide(.object(["role": .string("user")])))
        XCTAssertTrue(LocalStore.isUserSide(.object(["role": .string("session"), "content": .object(["role": .string("user"), "ev": .object(["t": .string("text")])])])))
        XCTAssertTrue(LocalStore.isUserSide(.object(["role": .string("session"), "content": .object(["role": .string("agent"), "ev": .object(["t": .string("user-message-accepted")])])])))
        XCTAssertFalse(LocalStore.isUserSide(.object(["role": .string("session"), "content": .object(["role": .string("agent"), "ev": .object(["t": .string("turn-end")])])])))
        XCTAssertFalse(LocalStore.isUserSide(.object(["role": .string("agent"), "content": .object(["type": .string("event"), "data": .object(["type": .string("ready")])])])))
        XCTAssertFalse(LocalStore.isUserSide(nil))
    }
}
