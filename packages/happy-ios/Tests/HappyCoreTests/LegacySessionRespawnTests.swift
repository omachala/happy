import Foundation
import XCTest
@testable import HappyCore
import HappyStore
import HappyWire

/// The fork's trash: kill (or archive), respawn in the same place with the
/// same harness, carry the permission and model picks over.
final class LegacySessionRespawnTests: XCTestCase {
    private final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var _steps: [String] = []
        var steps: [String] { lock.withLock { _steps } }
        func add(_ step: String) { lock.withLock { _steps.append(step) } }
    }

    private func record(_ metadata: [String: JSONValue], active: Bool = true) -> SessionRecord {
        var record = ChatRecords.storeSession("old", metadata: .object(metadata))
        record.active = active
        return record
    }

    private let place: [String: JSONValue] = ["machineId": .string("m1"), "path": .string("/work/app"), "flavor": .string("claude")]

    func testTheTrashShowsOnlyForAConnectedSessionThatNamesItsPlace() {
        XCTAssertEqual(LegacySessionRespawn.plan(record(place)), LegacySessionRespawn.Plan(machineId: "m1", directory: "/work/app", agent: "claude"))
        XCTAssertNil(LegacySessionRespawn.plan(record(place, active: false)), "disconnected")
        XCTAssertNil(LegacySessionRespawn.plan(record(["path": .string("/work/app")])), "no machine")
        XCTAssertNil(LegacySessionRespawn.plan(record(["machineId": .string("m1")])), "no directory")
        XCTAssertNil(LegacySessionRespawn.plan(record(["machineId": .string("m1"), "path": .string("")])))
        XCTAssertNil(LegacySessionRespawn.plan(nil))
        var rig = place
        rig["client"] = .object(["id": .string("rig")])
        rig["rigMetadataVersion"] = .number(1)
        XCTAssertNil(LegacySessionRespawn.plan(record(rig)), "Happy Agent starts its own way")
    }

    func testTheAgentFollowsTheFlavor() {
        for flavor in ["codex", "gemini", "openclaw", "agy", "opencode"] {
            XCTAssertEqual(LegacySessionRespawn.agent(flavor: flavor), flavor)
        }
        XCTAssertEqual(LegacySessionRespawn.agent(flavor: "claude"), "claude")
        XCTAssertEqual(LegacySessionRespawn.agent(flavor: nil), "claude")
        XCTAssertEqual(LegacySessionRespawn.agent(flavor: "rig"), "claude")
    }

    private func steps(_ log: Log, killed: Bool, spawn: SpawnSessionResult, archive: Error? = nil) -> LegacySessionRespawn.Steps {
        LegacySessionRespawn.Steps(
            kill: { id in log.add("kill \(id)"); return killed },
            archive: { id in log.add("archive \(id)"); if let archive { throw archive } },
            spawn: { options in log.add("spawn \(options.machineId) \(options.directory) \(options.agent ?? "-")"); return spawn },
            refreshSessions: { log.add("refresh") },
            copyPicks: { from, to in log.add("copy \(from)->\(to)") }
        )
    }

    func testAKilledSessionIsReplacedInItsPlace() async throws {
        let log = Log()
        let plan = LegacySessionRespawn.Plan(machineId: "m1", directory: "/work/app", agent: "codex")
        let id = try await LegacySessionRespawn.run(sessionId: "old", plan: plan, steps: steps(log, killed: true, spawn: .success(sessionId: "new")))
        XCTAssertEqual(id, "new")
        XCTAssertEqual(log.steps, ["kill old", "spawn m1 /work/app codex", "refresh", "copy old->new"])
    }

    func testASessionThatCannotBeKilledIsArchived() async throws {
        let log = Log()
        let plan = LegacySessionRespawn.Plan(machineId: "m1", directory: "/w", agent: "claude")
        _ = try await LegacySessionRespawn.run(sessionId: "old", plan: plan, steps: steps(log, killed: false, spawn: .success(sessionId: "new")))
        XCTAssertEqual(log.steps, ["kill old", "archive old", "spawn m1 /w claude", "refresh", "copy old->new"])
    }

    func testAFailedSpawnSaysWhy() async {
        let plan = LegacySessionRespawn.Plan(machineId: "m1", directory: "/w", agent: "claude")
        for (result, message) in [
            (SpawnSessionResult.error(errorMessage: "Daemon is gone"), "Daemon is gone"),
            (.error(errorMessage: ""), "Failed to start new session"),
            (.requestToApproveDirectoryCreation(directory: "/w"), "Failed to start new session"),
        ] {
            let log = Log()
            do {
                _ = try await LegacySessionRespawn.run(sessionId: "old", plan: plan, steps: steps(log, killed: true, spawn: result))
                XCTFail("expected a failure")
            } catch {
                XCTAssertEqual(error as? LegacySessionRespawn.Failure, .failed(message))
                XCTAssertEqual((error as? LocalizedError)?.errorDescription, message)
            }
            XCTAssertFalse(log.steps.contains("refresh"), "nothing after a failed spawn")
        }
    }

    func testAFailedArchiveStopsBeforeTheSpawn() async {
        let log = Log()
        let plan = LegacySessionRespawn.Plan(machineId: "m1", directory: "/w", agent: "claude")
        do {
            _ = try await LegacySessionRespawn.run(sessionId: "old", plan: plan, steps: steps(log, killed: false, spawn: .success(sessionId: "new"), archive: SessionActionError.botNeedsMachine))
            XCTFail("expected a failure")
        } catch {}
        XCTAssertEqual(log.steps, ["kill old", "archive old"])
    }

    func testThePermissionAndModelPicksCarryOverLocallyButNotTheEffort() throws {
        let store = try LocalStore.inMemory()
        try store.saveComposerState(ComposerStateRecord(sessionId: "old", values: .object([
            "permissionMode": .string("plan"), "modelMode": .string("claude-sonnet-5-5"), "effortLevel": .string("max"),
        ])))
        try store.saveComposerState(ComposerStateRecord(sessionId: "new", values: .object(["effortLevel": .string("high")])))
        try LegacySessionRespawn.copyPicks(store: store, from: "old", to: "new")
        XCTAssertEqual(try store.composerState(sessionId: "new").values, .object([
            "permissionMode": .string("plan"), "modelMode": .string("claude-sonnet-5-5"), "effortLevel": .string("high"),
        ]))
        // Nothing picked: nothing written over.
        try LegacySessionRespawn.copyPicks(store: store, from: "none", to: "fresh")
        XCTAssertEqual(try store.composerState(sessionId: "fresh").values, .object([:]))
    }
}
