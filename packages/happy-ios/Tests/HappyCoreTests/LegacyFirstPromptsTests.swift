import Foundation
import GRDB
import XCTest
@testable import HappyCore
import HappyStore
import HappyWire

/// The fork's fallback chat name: an untitled live chat's earliest stored
/// user text, `displayText` first (storage.ts `applyMessages`).
final class LegacyFirstPromptsTests: XCTestCase {
    private typealias F = LegacyHomeFixtures
    private var store: LocalStore!

    override func setUpWithError() throws {
        store = try LocalStore.inMemory()
    }

    private func message(_ id: String, in session: String, seq: Int, at: Int64, _ content: JSONValue) -> MessageRecord {
        MessageRecord(id: id, sessionId: session, seq: seq, localId: nil, createdAt: at, updatedAt: at, contentCipher: "c", content: content)
    }

    private func user(_ text: String, displayText: String? = nil) -> JSONValue {
        var record: [String: JSONValue] = ["role": .string("user"), "content": .object(["type": .string("text"), "text": .string(text)])]
        if let displayText { record["meta"] = .object(["displayText": .string(displayText)]) }
        return .object(record)
    }

    private func titles() throws -> [String: String] {
        try store.writer.read { try LegacyFirstPrompts.fetch($0) }
    }

    func testTheEarliestUserTextOfUntitledLiveChats() throws {
        try store.upsertSessions([
            F.session("plain", machine: "m1", path: "/w"),
            F.session("shown", machine: "m1", path: "/w"),
            F.session("terminal", machine: "m1", path: "/w"),
            F.session("named", machine: "m1", path: "/w", title: "Agent's title"),
            F.session("ended", machine: "m1", path: "/w", active: false),
            F.session("silent", machine: "m1", path: "/w"),
        ])
        let agent = ChatRecords.session("a", at: 5, role: "agent", event: .object(["t": .string("text"), "text": .string("agent words")]))
        try store.applyMessagePages([
            MessagePageWrite(sessionId: "plain", messages: [
                message("p1", in: "plain", seq: 1, at: 10, agent),
                message("p2", in: "plain", seq: 2, at: 20, user("  first\n\nprompt  ")),
                message("p3", in: "plain", seq: 3, at: 30, user("second prompt")),
            ]),
            MessagePageWrite(sessionId: "shown", messages: [message("s1", in: "shown", seq: 1, at: 10, user("/review 12", displayText: "Review PR 12"))]),
            MessagePageWrite(sessionId: "terminal", messages: [
                message("t1", in: "terminal", seq: 1, at: 10, ChatRecords.session("e1", at: 10, role: "user", turn: nil, event: .object(["t": .string("text"), "text": .string("typed in the terminal")]))),
            ]),
            MessagePageWrite(sessionId: "named", messages: [message("n1", in: "named", seq: 1, at: 10, user("ignored"))]),
            MessagePageWrite(sessionId: "ended", messages: [message("e1", in: "ended", seq: 1, at: 10, user("ignored"))]),
            MessagePageWrite(sessionId: "silent", messages: [message("q1", in: "silent", seq: 1, at: 10, agent)]),
        ])
        XCTAssertEqual(try titles(), [
            "plain": "first prompt",
            "shown": "Review PR 12",
            "terminal": "typed in the terminal",
        ])
    }

    /// The chat header's fallback reads one chat, ended or not.
    func testOneChatsTitleForItsHeader() throws {
        try store.upsertSessions([F.session("ended", machine: "m1", path: "/w", active: false), F.session("silent", machine: "m1", path: "/w")])
        try store.applyMessagePages([
            MessagePageWrite(sessionId: "ended", messages: [
                message("e2", in: "ended", seq: 2, at: 20, user("later")),
                message("e1", in: "ended", seq: 1, at: 10, user("  what   broke? ")),
            ]),
        ])
        XCTAssertEqual(try LegacyFirstPrompts.title(store, sessionId: "ended"), "what broke?")
        XCTAssertNil(try LegacyFirstPrompts.title(store, sessionId: "silent"))
    }

    /// An older page landing later moves the name to the true first prompt.
    func testAnOlderPageConvergesOnTheFirstPrompt() throws {
        try store.upsertSessions([F.session("s", machine: "m1", path: "/w")])
        try store.applyMessagePages([MessagePageWrite(sessionId: "s", messages: [message("m5", in: "s", seq: 5, at: 50, user("later"))])])
        XCTAssertEqual(try titles(), ["s": "later"])
        try store.applyMessagePages([MessagePageWrite(sessionId: "s", messages: [message("m1", in: "s", seq: 1, at: 10, user("earliest"))])])
        XCTAssertEqual(try titles(), ["s": "earliest"])
    }

    func testTheStreamHearsANewPrompt() async throws {
        try store.upsertSessions([F.session("s", machine: "m1", path: "/w")])
        let stream = LegacyFirstPrompts.snapshots(store)
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first, [:])
        try store.applyMessagePages([MessagePageWrite(sessionId: "s", messages: [message("m1", in: "s", seq: 1, at: 10, user("hello there"))], syncedThrough: 1)])
        let next = await iterator.next()
        XCTAssertEqual(next, ["s": "hello there"])
    }
}
