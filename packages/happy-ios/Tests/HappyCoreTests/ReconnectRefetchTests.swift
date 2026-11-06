import Foundation
import XCTest
@testable import HappyCore
import HappyCrypto
import HappyStore
import HappyWire

/// The fork's reconnect refetch: a socket (re)connect pulls the open chat's
/// messages, even while the session list hasn't caught up with them, and
/// leaves the session's live thinking alone.
final class ReconnectRefetchTests: XCTestCase {
    private var fixture: ServerFixture!
    private var http: FakeHTTP!
    private var store: LocalStore!
    private var engine: LegacySyncEngine!

    override func setUpWithError() throws {
        fixture = ServerFixture()
        http = FakeHTTP()
        store = try LocalStore.inMemory()
        var options = LegacySyncEngine.Options()
        options.backoff = Backoff(initial: .milliseconds(1), maximum: .milliseconds(2))
        engine = LegacySyncEngine(api: testAPI(http), store: store, keys: fixture.keys, options: options)
        http.onRaw("GET /v1/machines", "[]")
        http.onRaw("GET /v1/account/settings", #"{"settings":null,"settingsVersion":0}"#)
        http.onRaw("GET /v1/account/profile", #"{"id":"u1","timestamp":1,"firstName":null,"lastName":null,"username":null,"avatar":null,"github":null,"connectedServices":[]}"#)
        let fixture = self.fixture!
        // The list still says seq 2: what was said while the socket was
        // down hasn't reached it.
        http.on("GET /v2/sessions") { _ in
            (200, try JSONEncoder().encode(SessionsPage(sessions: [fixture.session("s", seq: 2, updatedAt: 1)], nextCursor: nil, hasNext: false)))
        }
        http.on("GET /v3/sessions/s/messages") { request in
            let after = Int(request.query("after_seq") ?? "") ?? -1
            let all = (1...3).map { fixture.message(seq: $0, text: "m\($0)") }.filter { $0.seq > after }
            return (200, try JSONEncoder().encode(MessagesPage(messages: all, hasMore: false)))
        }
        try store.upsertSessions([RecordDecoder(keyRing: KeyRing(keys: fixture.keys)).session(fixture.session("s", seq: 2, updatedAt: 1))])
        try store.applyMessagePage(sessionId: "s", messages: [], syncedThrough: 2)
        try store.applySessionActivity(id: "s", active: true, activeAt: 1, thinking: true)
    }

    override func tearDown() async throws {
        await engine.stop()
    }

    func testAReconnectRefetchesTheOpenChat() async throws {
        await engine.setViewing("s", true)
        await engine.syncAll()
        await engine.waitForIdle()
        XCTAssertEqual(http.requests("GET /v3/sessions/s/messages").map { $0.query("after_seq") }, ["2"])
        XCTAssertEqual(try store.messages(sessionId: "s").map(\.seq), [3])
        XCTAssertEqual(try store.session(id: "s")?.thinking, true, "the live thinking state is left alone")
    }

    func testAChatNoLongerOnScreenIsNotRefetched() async throws {
        await engine.setViewing("s", true)
        await engine.setViewing("s", true)
        await engine.setViewing("s", false)
        await engine.syncAll()
        await engine.waitForIdle()
        XCTAssertEqual(http.requests("GET /v3/sessions/s/messages").count, 1, "still open on one screen")

        await engine.setViewing("s", false)
        await engine.syncAll()
        await engine.waitForIdle()
        XCTAssertEqual(http.requests("GET /v3/sessions/s/messages").count, 1, "closed: the list's seq decides, and it is behind")
    }
}
