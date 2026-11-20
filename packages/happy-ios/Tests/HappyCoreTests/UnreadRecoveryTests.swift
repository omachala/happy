import Foundation
import XCTest
@testable import HappyCore
import HappyCrypto
import HappyStore
import HappyWire

/// A turn that ended while the app was suspended, killed or offline: the
/// live `session-event` never came, so the reconnect's session sync marks
/// it unread from the read marker (`LegacySyncEngine.recoverUnread`).
final class UnreadRecoveryTests: XCTestCase {
    var fixture: ServerFixture!
    var http: FakeHTTP!
    var store: LocalStore!
    var engine: LegacySyncEngine!
    var server: ServerSessions!
    var newest: NewestMessage!
    var clock: LegacySyncEngineTests.Clock!

    final class NewestMessage: @unchecked Sendable {
        var fromUser = false
    }

    override func setUpWithError() throws {
        fixture = ServerFixture()
        http = FakeHTTP()
        store = try LocalStore.inMemory()
        var options = LegacySyncEngine.Options()
        options.backoff = Backoff(initial: .milliseconds(1), maximum: .milliseconds(2))
        let clock = LegacySyncEngineTests.Clock()
        clock.now = 10_000_000
        self.clock = clock
        engine = LegacySyncEngine(api: testAPI(http), store: store, keys: fixture.keys, options: options, now: { clock.now })
        let fixture = self.fixture!
        let server = ServerSessions([fixture.session("s", seq: 2, updatedAt: 100), fixture.session("t", seq: 4, updatedAt: 100)])
        self.server = server
        let newest = NewestMessage()
        self.newest = newest
        http.on("GET /v2/sessions") { _ in (200, try JSONEncoder().encode(SessionsPage(sessions: server.value, nextCursor: nil, hasNext: false))) }
        for id in ["s", "t"] {
            http.on("GET /v3/sessions/\(id)/messages") { request in
                let after = Int(request.query("after_seq") ?? "") ?? 0
                let seq = server.value.first { $0.id == id }?.seq ?? 0
                guard seq > after else { return (200, try JSONEncoder().encode(MessagesPage(messages: [], hasMore: false))) }
                let message = newest.fromUser ? fixture.userMessage(seq: seq) : fixture.message(seq: seq, text: "done")
                return (200, try JSONEncoder().encode(MessagesPage(messages: [message], hasMore: false)))
            }
        }
    }

    override func tearDown() async throws {
        await engine.stop()
    }

    /// A reconnect: the session list, then the messages it says are new.
    private func sync() async {
        await engine.run(.sessions)
        await engine.waitForIdle()
    }

    private func unread(_ id: String) throws -> Bool { try XCTUnwrap(store.session(id: id)).unread }

    /// The server moved on while the app was away.
    private func turnEnded(_ id: String, seq: Int) {
        server.value = server.value.map { session in
            guard session.id == id else { return session }
            var moved = session
            moved.seq = seq
            moved.updatedAt += 1_000
            return moved
        }
    }

    func testTheFirstSyncLightsNothing() async throws {
        await sync()
        XCTAssertFalse(try unread("s"))
        XCTAssertFalse(try unread("t"))
        XCTAssertEqual(http.requests("GET /v3/sessions/s/messages").map { $0.query("limit") }, ["100"], "the history pull alone, no newest-message ask")
    }

    func testATurnMissedWhileBackgroundedIsUnreadAfterTheSync() async throws {
        await sync()
        turnEnded("s", seq: 5)
        await sync()
        XCTAssertTrue(try unread("s"))
        XCTAssertFalse(try unread("t"), "nothing new there")
    }

    /// What is not on disk yet is asked for from the marker on, at most
    /// the newest few (a turn ends with housekeeping after what was said).
    func testOnlyTheMessagesPastTheMarkerAreAskedFor() async throws {
        await sync()
        let decoder = RecordDecoder(keyRing: KeyRing(keys: fixture.keys))
        try store.upsertSessions([decoder.session(fixture.session("s", seq: 5, updatedAt: 2_000))])
        await engine.recoverUnread()
        XCTAssertEqual(http.requests("GET /v3/sessions/s/messages").last?.query("after_seq"), "2")
        XCTAssertEqual(http.requests("GET /v3/sessions/s/messages").last?.query("limit"), "3")
        XCTAssertTrue(try unread("s"))
    }

    /// The agent pings every couple of seconds through a turn; thinking
    /// started long ago does not make the turn over. Only its end does.
    func testATurnLongerThanAMinuteIsNotFlaggedMidTurn() async throws {
        await sync()
        let start = clock.now
        let ping = { (offset: Int64, thinking: Bool) async in
            self.clock.now = start + offset
            await self.engine.presence.activity(id: "s", active: true, activeAt: start + offset, thinking: thinking)
        }
        await ping(0, true)
        await ping(30_000, true)
        await ping(59_000, true)
        turnEnded("s", seq: 5)
        clock.now = start + 90_000
        await sync()
        XCTAssertFalse(try unread("s"), "pinged 31 s ago: still on its turn, 90 s after it began")

        await ping(150_000, true)
        clock.now = start + 200_000
        await sync()
        XCTAssertFalse(try unread("s"), "still on its turn after three minutes")

        await ping(210_000, false)
        await sync()
        XCTAssertTrue(try unread("s"), "the turn ended")
    }

    /// Thinking when the app went away: after a reconnect it is held back
    /// until its first ping since has had time to come, then judged by it.
    func testAThinkingSessionWaitsForItsFirstPingAfterAResume() async throws {
        await sync()
        let start = clock.now
        await engine.presence.activity(id: "s", active: true, activeAt: start, thinking: true)
        turnEnded("s", seq: 5)

        clock.now = start + 300_000
        await engine.noteResumed()
        await sync()
        XCTAssertFalse(try unread("s"), "the first ping since the resume has not had time to come")

        await engine.presence.activity(id: "s", active: true, activeAt: start + 302_000, thinking: true)
        clock.now = start + 312_000
        await engine.recoverUnread()
        XCTAssertFalse(try unread("s"), "it pinged: still on its turn")

        await engine.presence.activity(id: "s", active: true, activeAt: start + 320_000, thinking: false)
        clock.now = start + 320_000
        await engine.recoverUnread()
        XCTAssertTrue(try unread("s"), "the turn ended")
    }

    /// Thinking when the app went away and never pinged again (the agent
    /// died): flagged once the grace after the reconnect is over.
    func testAThinkingSessionThatNeverPingsAgainIsFlaggedAfterTheGrace() async throws {
        await sync()
        let start = clock.now
        await engine.presence.activity(id: "s", active: true, activeAt: start, thinking: true)
        turnEnded("s", seq: 5)

        clock.now = start + 300_000
        await engine.noteResumed()
        await sync()
        XCTAssertFalse(try unread("s"))

        clock.now = start + 300_000 + LegacySyncEngine.unreadPingGraceMs
        await engine.recoverUnread()
        XCTAssertTrue(try unread("s"))
    }

    func testTheOwnMessageDoesNotFlag() async throws {
        await sync()
        newest.fromUser = true
        turnEnded("s", seq: 3)
        await sync()
        XCTAssertFalse(try unread("s"))

        let fetched = http.requests("GET /v3/sessions/s/messages").count
        await sync()
        XCTAssertEqual(http.requests("GET /v3/sessions/s/messages").count, fetched, "the marker moved past it")

        newest.fromUser = false
        turnEnded("s", seq: 4)
        await sync()
        XCTAssertTrue(try unread("s"), "the agent's answer still counts")
    }

    func testTheChatOnScreenIsNeverFlagged() async throws {
        await sync()
        engine.viewing.show("s")
        turnEnded("s", seq: 5)
        await sync()
        XCTAssertFalse(try unread("s"))
    }

    func testOpeningClearsItAndItStaysRead() async throws {
        await sync()
        turnEnded("s", seq: 5)
        await sync()
        XCTAssertTrue(try unread("s"))

        try store.markSessionRead(id: "s")
        XCTAssertFalse(try unread("s"))
        await sync()
        XCTAssertFalse(try unread("s"), "read up to where the chat was")
    }

    func testAFailedFetchWaitsForTheNextSync() async throws {
        await sync()
        let decoder = RecordDecoder(keyRing: KeyRing(keys: fixture.keys))
        try store.upsertSessions([decoder.session(fixture.session("s", seq: 5, updatedAt: 2_000))])
        http.onRaw("GET /v3/sessions/s/messages", "{}", status: 500)
        await engine.recoverUnread()
        XCTAssertFalse(try unread("s"))
    }
}

extension ServerFixture {
    func userMessage(seq: Int) -> SessionMessage {
        let payload: JSONValue = .object(["role": .string("user"), "content": .object(["type": .string("text"), "text": .string("hi")])])
        return SessionMessage(id: "m\(seq)", seq: seq, localId: nil, content: SessionMessageContent(c: seal(payload)), createdAt: Int64(seq), updatedAt: Int64(seq))
    }
}
