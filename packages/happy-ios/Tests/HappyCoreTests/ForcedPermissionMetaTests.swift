import Foundation
import XCTest
@testable import HappyCore
import HappyStore
import HappyWire

/// The fork's messageMeta.ts: every Happy CLI message carries the agent's
/// never-ask permission, whatever was picked; model and effort are the
/// pick, else the settings' override, else the default.
final class ForcedPermissionMetaTests: XCTestCase {
    private func json(_ text: String) -> JSONValue { try! JSONValue.decode(Data(text.utf8)) }

    private func meta(
        flavor: String?, version: String? = "1.2.0", extra: [String: JSONValue] = [:],
        composer: JSONValue = .object([:]), overrides: JSONValue? = nil
    ) throws -> [String: JSONValue] {
        var metadata = extra
        if let flavor { metadata["flavor"] = .string(flavor) }
        if let version { metadata["version"] = .string(version) }
        let session = SessionRecord(
            id: "s", seq: 0, createdAt: 0, updatedAt: 0, active: true, activeAt: 0, projectId: nil,
            metadataVersion: 1, metadataCipher: "", metadata: .object(metadata), agentStateVersion: 1,
            agentStateCipher: nil, agentState: nil, dataKeyCipher: nil, decryptable: true
        )
        let settings: JSONValue? = overrides.map { .object(["agentDefaultOverrides": $0]) }
        let record = try UserMessageEncoder.encode(OutgoingMessage(text: "hi"), session: session, composer: composer, settings: settings)
        return try XCTUnwrap(record["meta"]?.objectValue)
    }

    func testEveryFlavorIsForcedToItsNeverAskMode() throws {
        let expected: [(String?, String)] = [
            ("claude", "bypassPermissions"), (nil, "bypassPermissions"), ("codex", "yolo"), ("gemini", "yolo"),
            ("openclaw", "bypassPermissions"), ("agy", "yolo"), ("opencode", "bypassPermissions"),
            ("something-new", "bypassPermissions"),
        ]
        for (flavor, permission) in expected {
            XCTAssertEqual(try meta(flavor: flavor)["permissionMode"], .string(permission), flavor ?? "nil")
        }
    }

    func testPicksOverridesAndPlanModeNeverReachThePermission() throws {
        let picked = json(#"{ "permissionMode": "plan" }"#)
        let overrides = json(#"{ "claude": { "permissionMode": "default" }, "codex": { "permissionMode": "read-only" } }"#)
        XCTAssertEqual(try meta(flavor: "claude", composer: picked, overrides: overrides)["permissionMode"], .string("bypassPermissions"))
        XCTAssertEqual(try meta(flavor: "codex", composer: picked, overrides: overrides)["permissionMode"], .string("yolo"))
        // `auto` on a CLI too old for it is overridden, not refused.
        XCTAssertEqual(try meta(flavor: "claude", version: "1.2.0", composer: json(#"{ "permissionMode": "auto" }"#))["permissionMode"], .string("bypassPermissions"))
    }

    func testModelAndEffortArePickThenOverrideThenDefault() throws {
        // Nothing picked: Opus 5.5 at high, sent even on the fork's 1.2.0.
        let fresh = try meta(flavor: "claude")
        XCTAssertEqual(fresh["model"], .string("claude-opus-5-5"))
        XCTAssertEqual(fresh["effort"], .string("high"))
        // Overrides.
        let overridden = try meta(flavor: "claude", overrides: json(#"{ "claude": { "modelMode": "claude-sonnet-5-5", "effortLevel": "low" } }"#))
        XCTAssertEqual(overridden["model"], .string("claude-sonnet-5-5"))
        XCTAssertEqual(overridden["effort"], .string("low"))
        // The session's pick wins.
        let picked = try meta(
            flavor: "claude", composer: json(#"{ "modelMode": "claude-fable-5-1", "effortLevel": "max" }"#),
            overrides: json(#"{ "claude": { "modelMode": "claude-sonnet-5-5", "effortLevel": "low" } }"#)
        )
        XCTAssertEqual(picked["model"], .string("claude-fable-5-1"))
        XCTAssertEqual(picked["effort"], .string("max"))
        // `default` is sent as null.
        XCTAssertEqual(try meta(flavor: "claude", composer: json(#"{ "modelMode": "default" }"#))["model"], .null)
        // Codex stays on medium.
        let codex = try meta(flavor: "codex")
        XCTAssertEqual(codex["model"], .string("gpt-6.1-sol"))
        XCTAssertEqual(codex["effort"], .string("medium"))
        // opencode: its model, no effort.
        let opencode = try meta(flavor: "opencode")
        XCTAssertEqual(opencode["model"], .string("cara/qwen3.8-27b"))
        XCTAssertNil(opencode["effort"])
    }

    func testAModelTheCLIReportsStandsForTheDefaultWhenNothingIsPicked() throws {
        // A `/model` typed in the terminal is not switched back.
        let observed = try meta(flavor: "claude", extra: ["currentAgentModel": .string("claude-fable-5-1-20260801")])
        XCTAssertEqual(observed["model"], .string("claude-fable-5-1"))
        // Not one the list names exactly: the default.
        let older = try meta(flavor: "claude", extra: ["currentAgentModel": .string("claude-opus-5")])
        XCTAssertEqual(older["model"], .string("claude-opus-5-5"))
        // A pick wins over it.
        let picked = try meta(flavor: "claude", extra: ["currentAgentModel": .string("claude-fable-5-1")], composer: json(#"{ "modelMode": "claude-haiku-4-5" }"#))
        XCTAssertEqual(picked["model"], .string("claude-haiku-4-5"))
    }

    func testAHappyAgentSessionKeepsItsOwnPermission() throws {
        let rig = try meta(
            flavor: "codex", version: nil,
            extra: ["rigMetadataVersion": .number(1), "client": .object(["id": .string("rig")]), "currentOperatingModeCode": .string("ask")]
        )
        XCTAssertEqual(rig["permissionMode"], .string("ask"))
    }

    func testANewSessionStartsInTheNeverAskModeWhateverTheDraftHeld() throws {
        let machine = MachineRecord(
            id: "m1", seq: 0, createdAt: 1, updatedAt: 1, active: true, activeAt: 1, metadataVersion: 1,
            metadataCipher: "", metadata: .object(["host": .string("box"), "homeDir": .string("/Users/me"), "happyCliVersion": .string("1.2.0")]),
            daemonStateVersion: 0, daemonStateCipher: nil, daemonState: nil, dataKeyCipher: nil, decryptable: true
        )
        for (agent, permission) in [(NewSessionDraft.Agent.claude, "bypassPermissions"), (.codex, "yolo"), (.opencode, "bypassPermissions")] {
            let launch = try NewSessionLaunch.resolve(
                draft: NewSessionDraft(selectedMachineId: "m1", selectedPath: "~/x", agentType: agent, pickedAgentType: agent, permissionMode: "default"),
                pickedAgent: agent, machines: [machine], sessions: [], agentDefaultOverrides: [:], prompt: "go", attachments: []
            ).get()
            XCTAssertEqual(launch.permissionMode, permission, agent.rawValue)
            if agent == .claude {
                XCTAssertEqual(launch.modelMode, "claude-opus-5-5")
                XCTAssertEqual(launch.effortLevel, "high", "pinned to the session, so the first message sends it")
            }
        }
    }
}
