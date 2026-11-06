import Foundation
import XCTest
@testable import HappyCore
import HappyWire

/// The fork's local wipe on "Context was reset" (`/clear`), and its drop of
/// leaked skill-file bodies.
final class ContextResetTests: XCTestCase {
    private func reset(_ id: String, at time: Int64) -> NormalizedChatRecord {
        ChatRecords.agentEvent(id, at: time, event: .object([
            "type": .string("message"), "message": .string("Context was reset"),
        ]))
    }

    private func ids(_ state: ChatReducer) -> [String] {
        state.messages.map(\.id)
    }

    func testAResetHidesEverythingBeforeItAndStillShowsItself() {
        var state = ChatReducer()
        _ = state.reduce([
            ChatRecords.user("u1", at: 100, text: "first"),
            ChatRecords.text("a1", at: 110),
            ChatRecords.call("c1", call: "call-1", at: 120),
        ])
        XCTAssertEqual(ids(state).count, 3)
        _ = state.reduce([reset("r", at: 200)])
        XCTAssertEqual(ids(state), ["r"])
        XCTAssertEqual(state.resetAt, 200)
        // What comes after shows as usual.
        _ = state.reduce([ChatRecords.user("u2", at: 300, text: "after"), ChatRecords.text("a2", at: 310)])
        XCTAssertEqual(ids(state), ["r", "u2", "a2:0"])
    }

    func testOlderRecordsArrivingLaterAreDropped() {
        var state = ChatReducer()
        _ = state.reduce([reset("r", at: 200), ChatRecords.user("u2", at: 300)])
        // An older page, or a replay of history.
        _ = state.reduce([ChatRecords.user("old", at: 100), ChatRecords.text("old-a", at: 150), ChatRecords.call("old-c", call: "old-call", at: 199)])
        XCTAssertEqual(ids(state), ["r", "u2"])
    }

    func testOneBatchHoldingHistoryAndTheResetShowsOnlyWhatFollows() {
        var state = ChatReducer()
        _ = state.reduce([
            ChatRecords.user("u1", at: 100),
            ChatRecords.text("a1", at: 150),
            reset("r", at: 200),
            ChatRecords.user("u2", at: 300),
        ])
        XCTAssertEqual(ids(state), ["r", "u2"])
    }

    func testANewerResetWipesAgainAndAnOlderOneChangesNothing() {
        var state = ChatReducer()
        _ = state.reduce([reset("r1", at: 200), ChatRecords.user("u2", at: 300)])
        _ = state.reduce([reset("r2", at: 400), ChatRecords.user("u3", at: 500)])
        XCTAssertEqual(ids(state), ["r2", "u3"])
        _ = state.reduce([reset("r0", at: 100)])
        XCTAssertEqual(ids(state), ["r2", "u3"], "an older reset is older history: dropped")
        XCTAssertEqual(state.resetAt, 400)
    }

    func testAPermissionFromBeforeTheResetStaysHidden() {
        var state = ChatReducer()
        let agentState = ChatRecords.json(#"{ "completedRequests": { "p1": { "tool": "Bash", "status": "approved", "createdAt": 100, "completedAt": 110 } } }"#)
        _ = state.reduce([ChatRecords.user("u1", at: 50)], agentState: agentState)
        XCTAssertTrue(ids(state).contains("permission:p1"))
        _ = state.reduce([reset("r", at: 200)], agentState: agentState)
        XCTAssertEqual(ids(state), ["r"])
        _ = state.reduce([ChatRecords.user("u2", at: 300)], agentState: agentState)
        XCTAssertEqual(ids(state), ["r", "u2"])
    }

    func testAToolAfterTheResetStillGetsItsResult() {
        var state = ChatReducer()
        _ = state.reduce([reset("r", at: 200), ChatRecords.call("c", call: "late", at: 300)])
        _ = state.reduce([ChatRecords.result("res", call: "late", at: 310)])
        guard case .toolCall(let tool)? = state.messages.last else { return XCTFail("no tool") }
        XCTAssertEqual(tool.tool.state, .completed)
    }

    func testTheFeedRebuildsTheSameWayFromDisk() throws {
        // A reducer rebuilt from every stored record (`FeedState.reset`)
        // lands where the incremental one did.
        let records = [ChatRecords.user("u1", at: 100), reset("r", at: 200), ChatRecords.user("u2", at: 300)]
        var incremental = ChatReducer()
        for record in records { _ = incremental.reduce([record]) }
        var whole = ChatReducer()
        _ = whole.reduce(records)
        XCTAssertEqual(ids(incremental), ids(whole))
    }

    // MARK: Skill bodies

    func testALeakedSkillBodyIsDropped() {
        for text in ["Base directory for this skill: /x/skills/pdf\n# PDF", "  \n\tBase directory for this skill: /y"] {
            let raw = ChatRecords.session("s", event: .object(["t": .string("text"), "text": .string(text), "thinking": .bool(false)]))
            XCTAssertNil(ChatNormalizer.normalize(id: "s", createdAt: 1, raw: raw), text)
        }
        let quoted = ChatRecords.session("q", event: .object(["t": .string("text"), "text": .string("The Base directory for this skill: is shown"), "thinking": .bool(false)]))
        XCTAssertNotNil(ChatNormalizer.normalize(id: "q", createdAt: 1, raw: quoted))
        // A person's own text is never dropped.
        let user = ChatRecords.session("u", role: "user", turn: nil, event: .object(["t": .string("text"), "text": .string("Base directory for this skill: mine"), "thinking": .bool(false)]))
        XCTAssertNotNil(ChatNormalizer.normalize(id: "u", createdAt: 1, raw: user))
    }
}
