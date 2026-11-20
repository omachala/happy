import Foundation
import XCTest
@testable import HappyCore
import HappyStore
import HappyWire

/// The fork's Happy CLI home (ActiveSessionsGroupCompact.tsx): live sessions
/// only, one section per computer A–Z, projects by their newest session.
final class LegacyMachineHomeTests: XCTestCase {
    private typealias F = LegacyHomeFixtures

    private func machine(_ id: String, name: String?, host: String? = nil) -> MachineRecord {
        var record = F.machine(id, active: true, name: name ?? "")
        var metadata: [String: JSONValue] = [:]
        if let name { metadata["displayName"] = .string(name) }
        if let host { metadata["host"] = .string(host) }
        record.metadata = .object(metadata)
        return record
    }

    /// `created` orders by creation; `activity` by the last meaningful message.
    private func session(_ id: String, machine: String?, path: String?, created: Int64, activity: Int64? = nil, title: String? = nil, active: Bool = true) -> SessionRecord {
        var record = F.session(id, machine: machine, path: path, active: active, at: created, title: title)
        if let activity, case .object(var metadata)? = record.metadata {
            metadata["lastMeaningfulMessageAt"] = .number(Double(activity))
            record.metadata = .object(metadata)
        }
        return record
    }

    private func snapshot(_ machines: [MachineRecord], _ sessions: [SessionRecord], byActivity: Bool = false) -> LegacyHomeSnapshot {
        LegacyHomeSnapshot(
            machines: MachinesSnapshot(synced: true, machines: machines),
            sessions: sessions,
            settings: SettingsSnapshot(pending: ["sortSessionsByActivity": .bool(byActivity)]),
            sessionsSynced: true
        )
    }

    func testOnlyLiveSessionsAreListed() {
        var archiving = session("archiving", machine: "m1", path: "/work/a", created: 5)
        archiving.archiving = true
        var archivedRig = session("archived-lifecycle", machine: "m1", path: "/work/a", created: 6)
        archivedRig.metadata = .object(["machineId": .string("m1"), "path": .string("/work/a"), "lifecycleState": .string("archived")])
        let side = F.session("side", machine: "m1", path: "/work/a", at: 7, metadata: ["isSideChat": .bool(true)])
        let home = LegacyMachineHome(snapshot([machine("m1", name: "Studio")], [
            session("live", machine: "m1", path: "/work/a", created: 1),
            session("ended", machine: "m1", path: "/work/a", created: 2, active: false),
            archiving, archivedRig, side,
        ]))
        XCTAssertEqual(home.sections.flatMap { $0.sessions.map(\.id) }, ["live"])
        XCTAssertEqual(home.sessionCount, 1)
    }

    func testEveryComputerHeadsItsSectionAToZ() {
        let home = LegacyMachineHome(snapshot([
            machine("m1", name: "studio"),
            machine("m2", name: nil, host: "Air.local"),
            machine("m3", name: nil),
        ], [
            session("a", machine: "m1", path: "/work/a", created: 3),
            session("b", machine: "m2", path: "/work/b", created: 2),
            session("c", machine: "m3", path: "/work/c", created: 1),
            session("d", machine: nil, path: "/work/d", created: 4),
            session("e", machine: "gone", path: "/work/e", created: 5),
        ]), words: .init(unknownMachine: "unknown", home: "Home"))
        // displayName, then host, then the id; no computer is `<unknown>`.
        XCTAssertEqual(home.sections.map(\.name), ["<unknown>", "Air.local", "gone", "m3", "studio"])
        XCTAssertEqual(home.sections.map(\.machineId), [nil, "m2", "gone", "m3", "m1"])
    }

    func testASingleComputerStillHasItsHeading() {
        let home = LegacyMachineHome(snapshot([machine("m1", name: "Studio")], [session("a", machine: "m1", path: "/work/a", created: 1)]))
        XCTAssertEqual(home.rows, [
            .machine(LegacyMachineHeader(machineId: "m1", name: "Studio", first: true, firstPath: "/work/a")),
            .session(LegacyMachineSessionRow(id: "a", projectName: "A", status: .waiting, stale: true)),
        ])
    }

    /// new/index.tsx: a computer's `+` clears the path, and the screen picks
    /// the first of the folders its sessions ran in, live or not, sorted.
    func testAComputersPlusStartsInItsFirstFolder() {
        let home = LegacyMachineHome(snapshot([machine("m1", name: "Studio"), machine("m2", name: "Air")], [
            session("a", machine: "m1", path: "/work/zeta", created: 3),
            session("b", machine: "m1", path: "/work/alpha", created: 2, active: false),
            session("c", machine: "m1", path: "/work/zeta/.dev/worktree/x", created: 1),
            session("d", machine: "m2", path: "/Users/me", created: 1),
            session("e", machine: nil, path: "/elsewhere", created: 4),
        ]))
        let headers = home.rows.compactMap { row -> LegacyMachineHeader? in
            if case .machine(let header) = row { return header }
            return nil
        }
        XCTAssertEqual(headers.map(\.machineId), [nil, "m2", "m1"])
        XCTAssertEqual(headers.map(\.firstPath), [nil, "/Users/me", "/work/alpha"])
    }

    /// Newest activity first, by session, whatever its project; a worktree
    /// keeps its repository's name and its own badge.
    func testSessionsByLatestActivity() {
        let now: Int64 = 10 * LegacyMachineHome.staleAfterMs
        let home = LegacyMachineHome(snapshot([machine("m1", name: "Studio")], [
            session("happy-old", machine: "m1", path: "/work/happy", created: now - 4_000),
            session("alpha", machine: "m1", path: "/work/alpha", created: now - 3_000),
            session("happy-tree", machine: "m1", path: "/work/happy/.dev/worktree/swift-ocean", created: now - 9_000, activity: now - 1_000),
            session("happy-new", machine: "m1", path: "/work/happy", created: now - 2_000),
        ]), now: now)
        let rows = home.sections[0].sessions
        XCTAssertEqual(rows.map(\.id), ["happy-tree", "happy-new", "alpha", "happy-old"])
        XCTAssertEqual(rows.map(\.projectName), ["Happy", "Happy", "Alpha", "Happy"])
        XCTAssertEqual(rows.map(\.worktreeName), ["swift-ocean", nil, nil, nil])
        XCTAssertEqual(rows.map(\.stale), [false, false, false, false])
    }

    /// Activity is the default now; the synced setting no longer picks
    /// creation order.
    func testActivityOrderWhateverTheSetting() {
        let now: Int64 = 10 * LegacyMachineHome.staleAfterMs
        let sessions = [
            session("older-but-busy", machine: "m1", path: "/work/a", created: now - 9_000, activity: now - 100),
            session("newer", machine: "m1", path: "/work/b", created: now - 5_000, activity: now - 1_000),
        ]
        for byActivity in [false, true] {
            let home = LegacyMachineHome(snapshot([machine("m1", name: "S")], sessions, byActivity: byActivity), now: now)
            XCTAssertEqual(home.sections[0].sessions.map(\.id), ["older-but-busy", "newer"])
        }
    }

    /// Opening or leaving a chat (or its newest message seen here) counts
    /// as activity, from `LegacyHomeSnapshot.activity`.
    func testOpeningAChatCountsAsActivity() {
        let now: Int64 = 10 * LegacyMachineHome.staleAfterMs
        var home = snapshot([machine("m1", name: "S")], [
            session("a", machine: "m1", path: "/work/a", created: now - 5_000),
            session("b", machine: "m1", path: "/work/b", created: now - 4_000),
        ])
        XCTAssertEqual(LegacyMachineHome(home, now: now).sections[0].sessions.map(\.id), ["b", "a"])
        home.activity = ["a": now - 10]
        XCTAssertEqual(LegacyMachineHome(home, now: now).sections[0].sessions.map(\.id), ["a", "b"])
    }

    /// A day without activity: below every fresh row, still by activity,
    /// muted. Exactly a day is not stale yet.
    func testStaleRowsSinkBelowTheRest() {
        let now: Int64 = 10 * LegacyMachineHome.staleAfterMs
        let day = LegacyMachineHome.staleAfterMs
        let home = LegacyMachineHome(snapshot([machine("m1", name: "S")], [
            session("two-days", machine: "m1", path: "/work/a", created: now - 2 * day),
            session("fresh", machine: "m1", path: "/work/b", created: now - 10 * 60_000),
            session("just-a-day", machine: "m1", path: "/work/c", created: now - day),
            session("day-and-a-bit", machine: "m1", path: "/work/d", created: now - day - 1),
        ]), now: now)
        let rows = home.sections[0].sessions
        XCTAssertEqual(rows.map(\.id), ["fresh", "just-a-day", "day-and-a-bit", "two-days"])
        XCTAssertEqual(rows.map(\.stale), [false, false, true, true])
    }

    /// Unread, working or asking is never stale, however old.
    func testUnreadThinkingAndAskingAreNeverStale() {
        let now: Int64 = 10 * LegacyMachineHome.staleAfterMs
        let old = now - 3 * LegacyMachineHome.staleAfterMs
        var unread = session("unread", machine: "m1", path: "/work/a", created: old - 3)
        unread.unread = true
        var thinking = session("thinking", machine: "m1", path: "/work/b", created: old - 2)
        thinking.thinking = true
        var asking = session("asking", machine: "m1", path: "/work/c", created: old - 1)
        asking.agentState = .object(["requests": .object(["r": .object([:])])])
        let idle = session("idle", machine: "m1", path: "/work/d", created: old)
        let home = LegacyMachineHome(snapshot([machine("m1", name: "S")], [unread, thinking, asking, idle]), now: now)
        let rows = home.sections[0].sessions
        XCTAssertEqual(rows.map(\.id), ["asking", "thinking", "unread", "idle"])
        XCTAssertEqual(rows.map(\.stale), [false, false, false, true])
        XCTAssertEqual(rows.map(\.status), [.permissionRequired, .thinking, .unread, .waiting])
    }

    /// Presence and `thinking` never move a row: only activity does.
    func testThinkingDoesNotReorder() {
        let now: Int64 = 10 * LegacyMachineHome.staleAfterMs
        var a = session("a", machine: "m1", path: "/work/a", created: now - 2_000)
        let b = session("b", machine: "m1", path: "/work/b", created: now - 1_000)
        let before = LegacyMachineHome(snapshot([machine("m1", name: "S")], [a, b]), now: now).sections[0].sessions.map(\.id)
        a.thinking = true
        a.activeAt = now
        let after = LegacyMachineHome(snapshot([machine("m1", name: "S")], [a, b]), now: now).sections[0].sessions.map(\.id)
        XCTAssertEqual(before, ["b", "a"])
        XCTAssertEqual(after, before)
    }

    func testProjectNames() {
        XCTAssertEqual(LegacyMachineHome.projectName("/work", homeDir: "/work", home: "Home"), "Home")
        XCTAssertEqual(LegacyMachineHome.projectName("/work/", homeDir: "/work", home: "Home"), "Home")
        XCTAssertEqual(LegacyMachineHome.projectName("/work/happy-app", homeDir: "/work", home: "Home"), "Happy-app")
        XCTAssertEqual(LegacyMachineHome.projectName("/srv/ünïcode", homeDir: "/work", home: "Home"), "Ünïcode")
        XCTAssertEqual(LegacyMachineHome.projectName("C:\\code\\repo", homeDir: nil, home: "Home"), "Repo")
        XCTAssertEqual(LegacyMachineHome.projectName("", homeDir: "/work", home: "Home"), "")
        XCTAssertEqual(LegacyMachineHome.repoPath("/r/.dev/worktree/x"), "/r")
        XCTAssertEqual(LegacyMachineHome.worktreeName("/r/.dev/worktree/x"), "x")
        XCTAssertNil(LegacyMachineHome.worktreeName("/r/x"))
    }

    func testTheChatsNameFallsBackToItsFirstPrompt() {
        let home = LegacyMachineHome(snapshot([machine("m1", name: "S")], [
            session("named", machine: "m1", path: "/work/a", created: 3, title: "Fix the build"),
            session("prompted", machine: "m1", path: "/work/a", created: 2),
            session("untitled", machine: "m1", path: "/work/a", created: 1),
        ]), fallbackTitles: ["named": "ignored", "prompted": "Why does it crash"])
        XCTAssertEqual(home.sections[0].sessions.map(\.title), ["Fix the build", "Why does it crash", nil])
    }

    func testTitlesFromText() {
        XCTAssertEqual(LegacyMachineHome.title(fromText: "  hello \n\n  world\t "), "hello world")
        let long = String(repeating: "a", count: 79) + " bcd"
        XCTAssertEqual(LegacyMachineHome.title(fromText: long), String(repeating: "a", count: 79) + "…", "cut at 80, trailing space trimmed")
        XCTAssertEqual(LegacyMachineHome.title(fromText: String(repeating: "x", count: 80)), String(repeating: "x", count: 80))
        XCTAssertEqual(LegacyMachineHome.title(fromText: "   "), "")
    }

    func testTheDotUnreadFirstThenState() {
        func status(_ configure: (inout SessionRecord) -> Void) -> LegacyMachineSessionStatus {
            var record = F.session("s", machine: "m1", path: "/w")
            configure(&record)
            return LegacyMachineSessionStatus(record)
        }
        let permission: JSONValue = .object(["requests": .object(["r": .object([:])])])
        XCTAssertEqual(status { _ in }, .waiting)
        XCTAssertEqual(status { $0.thinking = true }, .thinking)
        XCTAssertEqual(status { $0.agentState = permission; $0.thinking = true }, .permissionRequired)
        XCTAssertEqual(status { $0.active = false }, .disconnected)
        XCTAssertEqual(status { $0.unread = true; $0.thinking = true; $0.agentState = permission }, .unread, "unread wins")
        XCTAssertTrue(LegacyMachineSessionStatus.thinking.pulses)
        XCTAssertTrue(LegacyMachineSessionStatus.permissionRequired.pulses)
        XCTAssertFalse(LegacyMachineSessionStatus.unread.pulses)
    }

    // MARK: Home

    func testHomeShowsTheSectionsInCardsAndNoArchive() throws {
        let snapshot = F.snapshot(grouping: "flat")
        let state = HomeState(snapshot, unknownMachine: "unknown", machineSections: .init())
        guard case .list(let list, _) = state else { return XCTFail("\(state)") }
        XCTAssertFalse(list.hasArchived)
        let model = HomeListModel(list, offline: nil, expandedProjects: [])
        XCTAssertTrue(model.machineSections)
        XCTAssertEqual(model.ids, [
            .machineHeader(""), .machineSession("s5"),
            .machineHeader("m2"), .machineSession("s4"),
            .machineHeader("m1"), .machineSession("b1"), .machineSession("s1"), .machineSession("s3"), .machineSession("s2"),
        ])
        // One card per computer; the headings stand outside them.
        XCTAssertNil(model.places[0])
        XCTAssertEqual(model.places[1], HomeCardPlace(first: true, last: true, separated: false))
        XCTAssertEqual(model.places[5], HomeCardPlace(first: true, last: false, separated: true))
        XCTAssertEqual(model.places[8], HomeCardPlace(first: false, last: true, separated: false))
        XCTAssertEqual(model.rows[0].sessionId, nil)
        XCTAssertEqual(model.rows[1].sessionId, "s5")
    }

    func testNoLiveSessionsIsNoSessionsEvenWithAnArchive() {
        let snapshot = LegacyHomeSnapshot(
            machines: MachinesSnapshot(synced: true, machines: [F.machine("m1", active: true, name: "Studio")]),
            sessions: [F.session("old", machine: "m1", path: "/work/a", active: false)],
            sessionsSynced: true
        )
        XCTAssertEqual(HomeState(snapshot, machineSections: .init()), .noSessions)
        XCTAssertNotEqual(HomeState(snapshot), .noSessions, "upstream's flat list shows the archive")
    }

    /// One session's unread flipping reconfigures that row alone.
    func testAnUnreadFlipTouchesOneRow() throws {
        var input = HomeDerivation.Input(snapshot: F.snapshot(), clock: ApplyPerfFixtures.clock)
        input.machineSections = .init()
        let (first, applied) = try XCTUnwrap(HomeDerivation.derive(input, applied: HomeDerivation.Applied()))
        XCTAssertEqual(first.content.kind, .list)
        var next = F.snapshot()
        let index = try XCTUnwrap(next.sessions.firstIndex { $0.id == "s1" })
        next.sessions[index].unread = true
        input.snapshot = next
        let (update, _) = try XCTUnwrap(HomeDerivation.derive(input, applied: applied))
        XCTAssertEqual(update.changeset.touchedRows, 1)
        XCTAssertNil(update.archiveModels)
    }

    func testAFirstPromptArrivingRenamesOneRow() throws {
        var snapshot = F.snapshot()
        snapshot.sessions.append(F.session("u1", machine: "m1", path: "/work/beta"))
        var input = HomeDerivation.Input(snapshot: snapshot, clock: ApplyPerfFixtures.clock)
        input.machineSections = .init()
        input.preparesArchives = true
        let (_, applied) = try XCTUnwrap(HomeDerivation.derive(input, applied: HomeDerivation.Applied()))
        input.machineSections?.fallbackTitles = ["s1": "ignored: s1 has a summary", "u1": "Hello"]
        let (update, _) = try XCTUnwrap(HomeDerivation.derive(input, applied: applied))
        XCTAssertEqual(update.changeset.touchedRows, 1)
        XCTAssertNil(update.archiveModels, "the fork's home prepares no archive")
    }
}
