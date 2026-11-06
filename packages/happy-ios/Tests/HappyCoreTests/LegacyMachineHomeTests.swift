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
            .session(LegacyMachineSessionRow(id: "a", projectName: "A", status: .waiting)),
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

    /// Projects in the order of their newest session, newest first inside
    /// each, then flattened; a worktree sits with its repository.
    func testProjectsByTheirNewestSessionAndWorktreesWithTheirRepository() {
        let home = LegacyMachineHome(snapshot([machine("m1", name: "Studio")], [
            session("happy-old", machine: "m1", path: "/work/happy", created: 1),
            session("alpha", machine: "m1", path: "/work/alpha", created: 2),
            session("happy-tree", machine: "m1", path: "/work/happy/.dev/worktree/swift-ocean", created: 3),
            session("happy-new", machine: "m1", path: "/work/happy", created: 4),
        ]))
        let rows = home.sections[0].sessions
        XCTAssertEqual(rows.map(\.id), ["happy-new", "happy-tree", "happy-old", "alpha"])
        XCTAssertEqual(rows.map(\.projectName), ["Happy", "Happy", "Happy", "Alpha"])
        XCTAssertEqual(rows.map(\.worktreeName), [nil, "swift-ocean", nil, nil])
    }

    func testActivityOrderWhenTheSettingIsOn() {
        let sessions = [
            session("older-but-busy", machine: "m1", path: "/work/a", created: 1, activity: 100),
            session("newer", machine: "m1", path: "/work/b", created: 2, activity: 10),
        ]
        let byCreation = LegacyMachineHome(snapshot([machine("m1", name: "S")], sessions, byActivity: false))
        XCTAssertEqual(byCreation.sections[0].sessions.map(\.id), ["newer", "older-but-busy"])
        let byActivity = LegacyMachineHome(snapshot([machine("m1", name: "S")], sessions, byActivity: true))
        XCTAssertEqual(byActivity.sections[0].sessions.map(\.id), ["older-but-busy", "newer"])
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
            .machineHeader("m1"), .machineSession("b1"), .machineSession("s1"), .machineSession("s2"), .machineSession("s3"),
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
