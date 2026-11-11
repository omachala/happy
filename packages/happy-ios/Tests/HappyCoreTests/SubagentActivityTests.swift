import Foundation
import XCTest
import HappyWire
@testable import HappyCore

/// The chat's count of Claude sub-agents at work, for the activity bar.
final class SubagentActivityTests: XCTestCase {
    private static let launched =
        "Async agent launched successfully. (This tool result is internal metadata.)\nagentId: a5efbcf14bf526645"

    private func notification(_ call: String, status: String = "completed", role: String = "user", id: String = "note")
        -> JSONValue
    {
        let text = """
            <task-notification>
            <task-id>a5efbcf14bf526645</task-id>
            <tool-use-id>\(call)</tool-use-id>
            <output-file>/tmp/tasks/a5efbcf14bf526645.output</output-file>
            <status>\(status)</status>
            <summary>Agent "Explore" completed</summary>
            </task-notification>
            """
        return ChatRecords.session(
            id, at: 900, role: role, turn: nil, event: .object(["t": .string("text"), "text": .string(text)]))
    }

    func testReadsFinishedToolUseIdsFromTaskNotifications() {
        let text = """
            <task-notification>
            <tool-use-id>toolu_a</tool-use-id>
            <status>completed</status>
            </task-notification>
            <task-notification><tool-use-id>toolu_b</tool-use-id><status>running</status></task-notification>
            <task-notification><tool-use-id> toolu_c </tool-use-id><status>failed</status></task-notification>
            """
        XCTAssertEqual(ChatNormalizer.finishedTaskCalls(text), ["toolu_a", "toolu_c"])
        XCTAssertEqual(ChatNormalizer.finishedTaskCalls("<task-notification>no ids</task-notification>"), [])
    }

    func testNotificationOnlyRecordIsInvisibleButCarriesFinishedCalls() throws {
        let record = try XCTUnwrap(ChatNormalizer.normalize(id: "note", createdAt: 900, raw: notification("toolu_a")))
        XCTAssertEqual(record.body, .agent([]))
        XCTAssertEqual(record.finishedTasks, ["toolu_a"])
    }

    func testForegroundAgentCountsUntilItsResult() {
        var reducer = ChatReducer()
        _ = reducer.reduce([
            ChatRecords.call("c1", call: "toolu_a", name: "Agent", input: .object(["prompt": .string("look")])),
            ChatRecords.call("c2", call: "toolu_b", name: "Task", input: .object(["prompt": .string("look")])),
            ChatRecords.call("c3", call: "toolu_c", name: "Bash"),
        ])
        XCTAssertEqual(reducer.runningSubagents, 2)
        _ = reducer.reduce([ChatRecords.result("r1", call: "toolu_a", result: "found it")])
        XCTAssertEqual(reducer.runningSubagents, 1)
        _ = reducer.reduce([ChatRecords.result("r2", call: "toolu_b", error: true, result: "interrupted")])
        XCTAssertEqual(reducer.runningSubagents, 0)
    }

    func testBackgroundAgentCountsUntilItsNotification() {
        var reducer = ChatReducer()
        _ = reducer.reduce([
            ChatRecords.call("c1", call: "toolu_a", name: "Agent", input: .object(["run_in_background": .bool(true)])),
            ChatRecords.call("c2", call: "toolu_b", name: "Agent"),
            ChatRecords.result("r1", call: "toolu_a", result: Self.launched),
            ChatRecords.result("r2", call: "toolu_b", result: Self.launched),
        ])
        XCTAssertEqual(reducer.runningSubagents, 2, "both returned at once and left their sub-agents running")

        let note = ChatRecords.normalized("note", at: 900, raw: notification("toolu_a"))
        let reduction = reducer.reduce([note])
        XCTAssertEqual(reducer.runningSubagents, 1)
        XCTAssertTrue(reduction.messages.isEmpty, "a notification draws no row")
        XCTAssertFalse(reducer.messages.contains { $0.id.hasPrefix("note") })

        _ = reducer.reduce([ChatRecords.normalized("note2", at: 901, raw: notification("toolu_b", status: "killed", id: "note2"))])
        XCTAssertEqual(reducer.runningSubagents, 0)
    }

    func testStillRunningNotificationKeepsTheAgentCounted() {
        var reducer = ChatReducer()
        // Nothing finished, nothing to show: the notification is dropped.
        XCTAssertNil(ChatNormalizer.normalize(id: "note", createdAt: 900, raw: notification("toolu_a", status: "running")))
        _ = reducer.reduce([
            ChatRecords.call("c1", call: "toolu_a", name: "Agent"),
            ChatRecords.result("r1", call: "toolu_a", result: Self.launched),
        ])
        XCTAssertEqual(reducer.runningSubagents, 1)
    }

    func testNotificationBeforeItsCallInTheSameBatchStillCloses() {
        // History pages can arrive newest first.
        var reducer = ChatReducer()
        _ = reducer.reduce([
            ChatRecords.normalized("note", at: 900, raw: notification("toolu_a")),
            ChatRecords.result("r1", call: "toolu_a", result: Self.launched),
            ChatRecords.call("c1", call: "toolu_a", name: "Agent"),
        ])
        XCTAssertEqual(reducer.runningSubagents, 0)
    }

    func testSidechainAgentCallsAreNotCountedAgain() {
        var reducer = ChatReducer()
        _ = reducer.reduce([
            ChatRecords.call("c1", call: "toolu_a", name: "Agent", input: .object(["prompt": .string("look")])),
            ChatRecords.call("c2", call: "toolu_inner", name: "Agent", parent: "toolu_a"),
        ])
        XCTAssertEqual(reducer.runningSubagents, 1)
    }
}
