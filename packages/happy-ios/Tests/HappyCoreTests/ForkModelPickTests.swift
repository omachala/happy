import Foundation
import XCTest
@testable import HappyCore
import HappyStore
import HappyWire

/// The fork's Claude model handling (versioned picks, the model the CLI
/// reports, the green chip), its high default effort and opencode.
final class ForkModelPickTests: XCTestCase {
    private typealias Options = ModelModeOptions

    private func json(_ text: String) -> JSONValue { try! JSONValue.decode(Data(text.utf8)) }

    // MARK: The list

    func testTheClaudeListIsTheForksExactly() {
        let models = Options.availableModels(flavor: "claude", metadata: json(#"{ "flavor": "claude" }"#))
        XCTAssertEqual(models.map(\.key), ["claude-fable-5-2", "claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-4-5"])
        XCTAssertEqual(models.map(\.name), ["fable 5.2", "opus 5.5", "sonnet 5.5", "haiku 4.5"])
        XCTAssertEqual(models.first?.description, "latest & most capable")
        XCTAssertFalse(models.contains { $0.key == "default" })
    }

    func testTheDefaultPickIsOpus55EvenOnTheForksOldCLI() {
        for version in ["1.2.0", "1.2.5", "1.2.6", "nonsense"] {
            let modes = ComposerModes(metadata: .object(["flavor": .string("claude"), "version": .string(version)]), picks: ComposerPicks(), agentDefaultOverrides: [:])
            XCTAssertEqual(modes.modelMode?.key, "claude-opus-5-5", version)
        }
    }

    func testALegacyPickHeadsTheListNamedForItsVersion() {
        let modes = ComposerModes(metadata: json(#"{ "flavor": "claude" }"#), picks: ComposerPicks(modelMode: "claude-opus-5"), agentDefaultOverrides: [:])
        XCTAssertEqual(modes.availableModels.first, ModeOption(key: "claude-opus-5", name: "opus 5"))
        XCTAssertEqual(modes.modelMode?.key, "claude-opus-5", "never silently the default")
        XCTAssertEqual(modes.availableModels.count, 5)
        // A session pinned to Fable 5.1 keeps it, named for its version, above 5.2.
        let fable51 = ComposerModes(metadata: json(#"{ "flavor": "claude" }"#), picks: ComposerPicks(modelMode: "claude-fable-5-1"), agentDefaultOverrides: [:])
        XCTAssertEqual(fable51.availableModels.first, ModeOption(key: "claude-fable-5-1", name: "fable 5.1"))
        XCTAssertEqual(fable51.modelMode?.key, "claude-fable-5-1")
        XCTAssertEqual(fable51.availableModels.map(\.key).dropFirst().first, "claude-fable-5-2")
        let unknown = ComposerModes(metadata: json(#"{ "flavor": "claude" }"#), picks: ComposerPicks(modelMode: "my-model"), agentDefaultOverrides: [:])
        XCTAssertEqual(unknown.availableModels.first, ModeOption(key: "my-model", name: "my-model"))
        let none = ComposerModes(metadata: json(#"{ "flavor": "claude" }"#), picks: ComposerPicks(modelMode: "default"), agentDefaultOverrides: [:])
        XCTAssertEqual(none.availableModels.count, 4, "default is no pick of its own")
    }

    func testHumanizedClaudeKeys() {
        XCTAssertEqual(AgentDefaults.humanizeClaudeModelKey("claude-opus-5"), "opus 5")
        XCTAssertEqual(AgentDefaults.humanizeClaudeModelKey("claude-fable-5-2"), "fable 5.2")
        XCTAssertEqual(AgentDefaults.humanizeClaudeModelKey("claude-fable-5-1"), "fable 5.1")
        XCTAssertEqual(AgentDefaults.humanizeClaudeModelKey("claude-haiku-4-5-20251001"), "claude-haiku-4-5-20251001")
        XCTAssertEqual(AgentDefaults.humanizeClaudeModelKey("gpt-5"), "gpt-5")
    }

    // MARK: Raw id to key (version-exact)

    func testARawModelIdMapsOntoExactlyItsKey() {
        let cases: [(String?, String?)] = [
            ("claude-opus-5-5", "claude-opus-5-5"),
            ("claude-opus-5-5-20260901", "claude-opus-5-5"),
            ("CLAUDE-OPUS-5-5", "claude-opus-5-5"),
            ("claude-fable-5-2[1m]", "claude-fable-5-2"),
            ("claude-fable-5-2-20261101", "claude-fable-5-2"),
            ("claude-fable-5-2-20261101[1m]", "claude-fable-5-2"),
            ("us.anthropic.claude-sonnet-5-5-v1:0", "claude-sonnet-5-5"),
            ("anthropic/claude-haiku-4-5", "claude-haiku-4-5"),
            ("claude-haiku-4-5-20251001", "claude-haiku-4-5"),
            // Not the same version: never confirmed as the newer pick.
            ("claude-opus-5", nil),
            ("claude-opus-5-20260101", nil),
            ("claude-sonnet-5", nil),
            // Fable 5.1 left the list for 5.2.
            ("claude-fable-5-1", nil),
            ("claude-fable-5-1-20260801", nil),
            ("opus", nil),
            ("gpt-6.1-sol", nil),
            ("", nil),
            (nil, nil),
        ]
        for (raw, key) in cases {
            XCTAssertEqual(AgentDefaults.claudeModelKey(fromModelId: raw), key, raw ?? "nil")
        }
    }

    // MARK: The model shown

    func testTheModelShownIsThePickThenWhatTheCLIRunsThenTheDefault() {
        let observed = json(#"{ "flavor": "claude", "version": "1.2.0", "currentAgentModel": "claude-fable-5-2-20261101", "currentModelCode": "claude-haiku-4-5" }"#)
        // A pick wins.
        XCTAssertEqual(ComposerModes(metadata: observed, picks: ComposerPicks(modelMode: "claude-sonnet-5-5"), agentDefaultOverrides: [:]).modelMode?.key, "claude-sonnet-5-5")
        // No pick: what the CLI says it runs (a `/model` in the terminal).
        XCTAssertEqual(ComposerModes(metadata: observed, picks: ComposerPicks(), agentDefaultOverrides: [:]).modelMode?.key, "claude-fable-5-2")
        // ... over the settings' default.
        let overrides = ["claude": json(#"{ "modelMode": "claude-sonnet-5-5" }"#)]
        XCTAssertEqual(ComposerModes(metadata: observed, picks: ComposerPicks(), agentDefaultOverrides: overrides).modelMode?.key, "claude-fable-5-2")
        // A model the list doesn't name exactly: the default.
        let older = json(#"{ "flavor": "claude", "currentAgentModel": "claude-opus-5", "currentModelCode": "claude-haiku-4-5" }"#)
        XCTAssertEqual(ComposerModes(metadata: older, picks: ComposerPicks(), agentDefaultOverrides: [:]).modelMode?.key, "claude-opus-5-5")
        XCTAssertEqual(ComposerModes(metadata: older, picks: ComposerPicks(), agentDefaultOverrides: overrides).modelMode?.key, "claude-sonnet-5-5")
    }

    // MARK: Green

    func testTheChipIsGreyOnOpenAndGreenOnANewMatchingMetadata() {
        var confirmation = ModelConfirmation()
        // The cached metadata already matches: still grey.
        XCTAssertFalse(confirmation.update(metadataVersion: 4, currentAgentModel: "claude-opus-5-5", selectedKey: "claude-opus-5-5"))
        XCTAssertFalse(confirmation.isConfirmed)
        XCTAssertFalse(confirmation.update(metadataVersion: 4, currentAgentModel: "claude-opus-5-5", selectedKey: "claude-opus-5-5"))
        XCTAssertFalse(confirmation.isConfirmed, "the same metadata again is not news")
        // A newer version naming another model: grey.
        XCTAssertFalse(confirmation.update(metadataVersion: 5, currentAgentModel: "claude-sonnet-5-5", selectedKey: "claude-opus-5-5"))
        XCTAssertFalse(confirmation.isConfirmed)
        // A newer version naming exactly the pick (the turn's end): green.
        XCTAssertTrue(confirmation.update(metadataVersion: 6, currentAgentModel: "claude-opus-5-5-20260901", selectedKey: "claude-opus-5-5"))
        XCTAssertTrue(confirmation.isConfirmed)
        // Stays green until the pick changes.
        XCTAssertFalse(confirmation.update(metadataVersion: 7, currentAgentModel: "claude-sonnet-5-5", selectedKey: "claude-opus-5-5"))
        XCTAssertTrue(confirmation.isConfirmed)
    }

    func testANewPickGoesGreyUntilANewerMetadataConfirmsIt() {
        var confirmation = ModelConfirmation()
        confirmation.update(metadataVersion: 1, currentAgentModel: nil, selectedKey: "claude-opus-5-5")
        confirmation.update(metadataVersion: 2, currentAgentModel: "claude-opus-5-5", selectedKey: "claude-opus-5-5")
        XCTAssertTrue(confirmation.isConfirmed)
        // Picked sonnet: grey, and the metadata seen now (still saying
        // sonnet from an earlier turn) can't confirm it.
        XCTAssertTrue(confirmation.update(metadataVersion: 2, currentAgentModel: "claude-sonnet-5-5", selectedKey: "claude-sonnet-5-5"))
        XCTAssertFalse(confirmation.isConfirmed)
        XCTAssertFalse(confirmation.update(metadataVersion: 2, currentAgentModel: "claude-sonnet-5-5", selectedKey: "claude-sonnet-5-5"))
        XCTAssertTrue(confirmation.update(metadataVersion: 3, currentAgentModel: "claude-sonnet-5-5", selectedKey: "claude-sonnet-5-5"))
        XCTAssertTrue(confirmation.isConfirmed)
    }

    func testAnOlderVersionTheCLIDoesNotNameExactlyNeverConfirms() {
        var confirmation = ModelConfirmation()
        confirmation.update(metadataVersion: 1, currentAgentModel: nil, selectedKey: "claude-opus-5-5")
        confirmation.update(metadataVersion: 2, currentAgentModel: "claude-opus-5", selectedKey: "claude-opus-5-5")
        XCTAssertFalse(confirmation.isConfirmed)
        confirmation.update(metadataVersion: 3, currentAgentModel: "claude-opus-5-5", selectedKey: nil)
        XCTAssertFalse(confirmation.isConfirmed, "nothing selected")
    }

    func testTheChatSeesEveryMetadataVersionOfAForkSession() {
        // The fork's CLI rewrites the same model at every turn's end: the
        // version is what moves, so the chat's state must carry it.
        var record = ChatRecords.storeSession(metadata: json(#"{ "flavor": "claude", "currentAgentModel": "claude-opus-5-5" }"#))
        let before = ChatSessionState.rendered(record)
        record.metadataVersion += 1
        XCTAssertNotEqual(ChatSessionState.rendered(record), before)
        // Other sessions' versions stay unread.
        var plain = ChatRecords.storeSession(metadata: json(#"{ "flavor": "claude" }"#))
        let plainBefore = ChatSessionState.rendered(plain)
        plain.metadataVersion += 1
        XCTAssertEqual(ChatSessionState.rendered(plain), plainBefore)
    }

    // MARK: Effort

    func testClaudesEffortDefaultsToHighAndCodexsToMedium() {
        let claude = ComposerModes(metadata: json(#"{ "flavor": "claude", "version": "1.2.0" }"#), picks: ComposerPicks(), agentDefaultOverrides: [:])
        XCTAssertEqual(claude.effortLevel?.key, "high")
        XCTAssertEqual(claude.availableEffortLevels.map(\.key), ["low", "medium", "high", "xhigh", "max"])
        let codex = ComposerModes(metadata: json(#"{ "flavor": "codex", "version": "1.2.0" }"#), picks: ComposerPicks(), agentDefaultOverrides: [:])
        XCTAssertEqual(codex.effortLevel?.key, "medium")
        XCTAssertEqual(ModelModeOptions.codexEffortLevels(model: "gpt-unknown").map(\.key), ["low", "medium", "high", "xhigh"])
        let fresh = ComposerModes.newSession(agentType: "claude", picks: ComposerPicks(), agentDefaultOverrides: [:], cliVersion: "1.2.0")
        XCTAssertEqual(fresh.effortLevel?.key, "high")
        XCTAssertEqual(fresh.modelMode?.key, "claude-opus-5-5")
    }

    // MARK: opencode

    func testOpencodeIsItsOwnAgent() {
        XCTAssertEqual(AgentDefaults.Agent(flavor: "opencode"), .opencode)
        XCTAssertEqual(NewSessionDraft.Agent(rawValue: "opencode")?.defaultsAgent, .opencode)
        let models = Options.availableModels(flavor: "opencode", metadata: json(#"{ "flavor": "opencode" }"#))
        XCTAssertEqual(models, [ModeOption(key: "cara/qwen3.8-27b", name: "qwen", description: "Cara · 32K")])
        XCTAssertEqual(Options.availablePermissionModes(flavor: "opencode", metadata: json(#"{ "flavor": "opencode" }"#)).map(\.key), ["default", "bypassPermissions"])
        XCTAssertEqual(Options.effortLevelsForModel(flavor: "opencode", modelKey: "cara/qwen3.8-27b"), [])
        let modes = ComposerModes(metadata: json(#"{ "flavor": "opencode" }"#), picks: ComposerPicks(), agentDefaultOverrides: [:])
        XCTAssertEqual(modes.modelMode?.key, "cara/qwen3.8-27b")
        XCTAssertNil(modes.effortLevel)
    }

    func testOpencodesPublishedModelsGetShortNames() {
        let metadata = json(#"{ "flavor": "opencode", "models": [{ "code": "cara/qwen3.8-27b", "value": "cara/qwen3.8-27b" }, { "code": "cara/llama4-70b", "value": "cara/llama4-70b" }] }"#)
        XCTAssertEqual(Options.availableModels(flavor: "opencode", metadata: metadata).map(\.name), ["qwen", "llama"])
        XCTAssertEqual(AgentDefaults.OpenCode.shortName(key: "x", name: "Mistral-7B"), "mistral")
        XCTAssertEqual(AgentDefaults.OpenCode.shortName(key: "x", name: "p/42"), "42")
    }

    func testOpencodeIsOfferedUnlessTheComputerSaysNo() {
        func choice(_ availability: JSONValue?) -> MachineChoice {
            var metadata: [String: JSONValue] = ["host": .string("host")]
            if let availability { metadata["cliAvailability"] = availability }
            let machine = MachineRecord(
                id: "m", seq: 0, createdAt: 1, updatedAt: 1, active: true, activeAt: 1, metadataVersion: 1,
                metadataCipher: "", metadata: .object(metadata), daemonStateVersion: 0, daemonStateCipher: nil,
                daemonState: nil, dataKeyCipher: nil, decryptable: true
            )
            return MachineChoice.collect([machine])[0]
        }
        XCTAssertTrue(choice(nil).availableAgents.contains("opencode"))
        XCTAssertTrue(choice(.object(["claude": .bool(true)])).availableAgents.contains("opencode"), "not probed")
        XCTAssertTrue(choice(.object(["opencode": .bool(true)])).availableAgents.contains("opencode"))
        XCTAssertFalse(choice(.object(["opencode": .bool(false)])).availableAgents.contains("opencode"))
    }
}
