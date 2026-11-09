import Foundation
import HappyWire

/// The defaults new sessions start with, per agent: happy-app's
/// sync/agentDefaults.ts and the option lists in
/// components/modelModeOptions.ts that Settings › Agents offers.
public enum AgentDefaults {
    public enum Agent: String, CaseIterable, Sendable {
        case claude
        case codex
        case gemini
        case openclaw
        case agy
        /// opencode against the local Qwen (the fork's `happy opencode`).
        case opencode

        /// utils/harnessCatalog.ts `HARNESS_NAMES`.
        public var name: String {
            switch self {
            case .claude: "Claude Code"
            case .codex: "Codex"
            case .gemini: "Gemini"
            case .openclaw: "OpenClaw"
            case .agy: "Antigravity"
            case .opencode: "opencode"
            }
        }

        /// Retired harnesses keep their stored defaults but are not offered.
        public var isRetired: Bool {
            self == .gemini || self == .openclaw
        }

        public static var configurable: [Agent] {
            allCases.filter { !$0.isRetired }
        }
    }

    public enum Field: String, CaseIterable, Sendable {
        case permissionMode
        case modelMode
        case effortLevel
    }

    public struct Option: Equatable, Sendable {
        public var key: String
        public var name: String
        public var description: String?

        public init(_ key: String, _ name: String, _ description: String? = nil) {
            self.key = key
            self.name = name
            self.description = description
        }
    }

    public struct Config: Equatable, Sendable {
        public var permissionMode: String
        public var modelMode: String
        public var effortLevel: String?

        public subscript(field: Field) -> String? {
            switch field {
            case .permissionMode: permissionMode
            case .modelMode: modelMode
            case .effortLevel: effortLevel
            }
        }
    }

    /// `auto` first shipped in this happy-cli.
    public static let cliVersionWithAuto = "1.2.1-beta.2"

    /// The fork (sync/agentDefaults.ts): every agent starts in its own
    /// never-ask mode, Claude on Opus 5.5 at high effort. Opus 5.5 is not
    /// gated on the CLI's version: the fork's CLI runs it but reports 1.2.0.
    static func codeDefaults(_ agent: Agent) -> Config {
        switch agent {
        case .claude: Config(permissionMode: "bypassPermissions", modelMode: "claude-opus-5-5", effortLevel: "high")
        case .codex: Config(permissionMode: "yolo", modelMode: "gpt-6.1-sol", effortLevel: "medium")
        case .gemini: Config(permissionMode: "yolo", modelMode: "gemini-2.5-pro", effortLevel: nil)
        case .openclaw: Config(permissionMode: "bypassPermissions", modelMode: "default", effortLevel: nil)
        case .agy: Config(permissionMode: "bypassPermissions", modelMode: "Gemini 3.8 Flash", effortLevel: "medium")
        case .opencode: Config(permissionMode: "bypassPermissions", modelMode: OpenCode.modelKey, effortLevel: nil)
        }
    }

    /// The code defaults for the CLI that will run them: an older CLI gets
    /// `default` instead of `auto`.
    public static func codeDefaults(_ agent: Agent, cliVersion: String?) -> Config {
        var config = codeDefaults(agent)
        if config.permissionMode == "auto", let cliVersion {
            if !SemanticVersion.isWellFormed(cliVersion) || SemanticVersion.compare(cliVersion, cliVersionWithAuto) < 0 {
                config.permissionMode = "default"
            }
        }
        return config
    }

    /// The permission every Happy CLI message carries, whatever was picked
    /// (the fork's `resolveMessageModeMeta`): the agent's never-ask mode.
    /// Happy Agent sessions keep their own.
    public static func forcedPermissionMode(_ agent: Agent) -> String {
        switch agent {
        case .claude, .openclaw, .opencode: "bypassPermissions"
        case .codex, .gemini, .agy: "yolo"
        }
    }

    /// opencode's one model: the local Qwen on Cara.
    public enum OpenCode {
        public static let modelKey = "cara/qwen3.8-27b"
        public static let models = [Option(modelKey, "qwen", "Cara · 32K")]

        /// `shortenOpenCodeModelName`: a known key's name, else the model
        /// without its `provider/`, cut to its leading letters, lowercased
        /// (`llama4-70b` → "llama").
        public static func shortName(key: String, name: String) -> String {
            if let known = models.first(where: { $0.key == key }) { return known.name }
            let bare = name.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? name
            let letters = bare.prefix(while: { $0.isASCII && $0.isLetter })
            return letters.isEmpty ? bare : letters.lowercased()
        }
    }

    // MARK: Claude models

    /// `humanizeClaudeModelKey`: "claude-opus-5" → "opus 5",
    /// "claude-fable-5-2" → "fable 5.2"; anything else as it is.
    public static func humanizeClaudeModelKey(_ key: String) -> String {
        guard let match = key.wholeMatch(of: /claude-([a-z]+)-([0-9]+)(?:-([0-9]+))?/) else { return key }
        let version = match.3.map { "\(match.2).\($0)" } ?? String(match.2)
        return "\(match.1) \(version)"
    }

    /// `getClaudeFamilyKeyFromModelId`: the picker key naming exactly the
    /// model a raw Anthropic id is (vendor prefix, `[1m]`, `:N`, `-vN` and a
    /// dated snapshot stripped), or nil. Version-exact on purpose:
    /// `claude-opus-5` is not Opus 5.5.
    public static func claudeModelKey(fromModelId rawModel: String?) -> String? {
        guard let rawModel, !rawModel.isEmpty else { return nil }
        var id = rawModel.lowercased()
        if let range = id.range(of: "claude-"), range.lowerBound > id.startIndex {
            id = String(id[range.lowerBound...])
        }
        if id.hasSuffix("[1m]") { id.removeLast(4) }
        if let match = id.firstMatch(of: /:[0-9]+$/) { id.removeSubrange(match.range) }
        if let match = id.firstMatch(of: /-v[0-9]+$/) { id.removeSubrange(match.range) }
        if let match = id.firstMatch(of: /-[0-9]{8}$/) { id.removeSubrange(match.range) }
        return hardcodedModels(.claude).contains(where: { $0.key == id }) ? id : nil
    }

    // MARK: Overrides

    static let retiredPermissionModes = ["dontAsk": "acceptEdits"]
    static let retiredClaudeModelModes = [
        "claude-opus-5-5[1m]": "claude-opus-5-5",
        "claude-opus-5[1m]": "claude-opus-5",
        "claude-sonnet-5-5[1m]": "claude-sonnet-5-5",
    ]

    /// Maps a stored flavor-agent permission key to the currently accepted key.
    /// Rig owns its own permission catalog and must not use this mapping.
    public static func retirePermissionMode(_ mode: String) -> String {
        retiredPermissionModes[mode] ?? mode
    }

    /// Mirrors permissionModeSupportedByCli; an absent CLI version is permissive.
    public static func permissionModeSupportedByCli(_ mode: String, cliVersion: String?) -> Bool {
        guard mode == "auto", let cliVersion, !cliVersion.isEmpty else {
            return true
        }
        return SemanticVersion.isWellFormed(cliVersion)
            && SemanticVersion.compare(cliVersion, cliVersionWithAuto) >= 0
    }

    /// The stored override for one field, with retired keys mapped onto the
    /// row that stands for them now.
    public static func override(_ overrides: [String: JSONValue], _ agent: Agent, _ field: Field) -> String? {
        guard let value = overrides[agent.rawValue]?[field.rawValue]?.stringValue else { return nil }
        switch field {
        case .permissionMode: return retirePermissionMode(value)
        case .modelMode: return agent == .claude ? retiredClaudeModelModes[value] ?? value : value
        case .effortLevel: return value
        }
    }

    public static func resolve(_ overrides: [String: JSONValue], _ agent: Agent, cliVersion: String?) -> Config {
        let code = codeDefaults(agent, cliVersion: cliVersion)
        return Config(
            permissionMode: override(overrides, agent, .permissionMode) ?? code.permissionMode,
            modelMode: override(overrides, agent, .modelMode) ?? code.modelMode,
            effortLevel: override(overrides, agent, .effortLevel) ?? code.effortLevel
        )
    }

    /// `setAgentDefaultOverride`: nil clears the field, and an agent with no
    /// fields left is removed.
    public static func setting(
        _ overrides: [String: JSONValue],
        _ agent: Agent,
        _ field: Field,
        to value: String?
    ) -> [String: JSONValue] {
        var next = overrides
        var current = next[agent.rawValue]?.objectValue ?? [:]
        if let value {
            current[field.rawValue] = .string(value)
        } else {
            current.removeValue(forKey: field.rawValue)
        }
        if Field.allCases.allSatisfy({ current[$0.rawValue] == nil }) {
            next.removeValue(forKey: agent.rawValue)
        } else {
            next[agent.rawValue] = .object(current)
        }
        return next
    }

    // MARK: Options

    public static func permissionModes(_ agent: Agent) -> [Option] {
        switch agent {
        case .claude:
            [
                Option("auto", "Auto", "asks when unsure"),
                Option("acceptEdits", "Edits", "edits, no asking"),
                Option("plan", "Plan", "plan first"),
                Option("bypassPermissions", "Yolo", "never asks"),
                Option("default", "Default", "harness setting"),
            ]
        case .codex:
            [
                Option("auto", "Auto", "asks when unsure"),
                Option("safe-yolo", "Workspace", "sandboxed, can escalate"),
                Option("read-only", "Read", "no writes"),
                Option("yolo", "Yolo", "full access"),
                Option("default", "Default", "codex setting"),
            ]
        case .gemini:
            [
                Option("yolo", "Yolo", "never asks"),
                Option("default", "Default", "harness setting"),
            ]
        case .openclaw:
            [
                Option("bypassPermissions", "Yolo", "not applied"),
                Option("default", "Default", "not applied"),
            ]
        case .agy:
            [
                Option("default", "Default", "agy sandbox"),
                Option("bypassPermissions", "Yolo", "never asks"),
            ]
        case .opencode:
            [
                Option("default", "Default", "harness setting"),
                Option("bypassPermissions", "Yolo", "never asks"),
            ]
        }
    }

    static func hardcodedModels(_ agent: Agent) -> [Option] {
        switch agent {
        case .claude:
            // The fork's list: each key is the exact `--model` sent, and
            // the name says that version. No "default" and no aliases.
            [
                Option("claude-fable-5-2", "fable 5.2", "latest & most capable"),
                Option("claude-opus-5-5", "opus 5.5"),
                Option("claude-sonnet-5-5", "sonnet 5.5"),
                Option("claude-haiku-4-5", "haiku 4.5"),
            ]
        case .codex:
            [
                Option("gpt-6-astra", "GPT-6 Astra", "most capable"),
                Option("gpt-6.1-sol", "GPT-6.1 Sol"),
                Option("gpt-6-sol", "GPT-6 Sol"),
                Option("gpt-6-luna", "GPT-6 Luna"),
                Option("gpt-5.6-sol", "GPT-5.6 Sol"),
                Option("gpt-5.6-terra", "GPT-5.6 Terra"),
                Option("gpt-5.6-luna", "GPT-5.6 Luna"),
            ]
        case .gemini:
            [
                Option("gemini-3.1-pro-preview", "Gemini 3.1 Pro", "latest & most capable"),
                Option("gemini-3-flash-preview", "Gemini 3 Flash", "latest & fast"),
                Option("gemini-3.1-flash-lite-preview", "Gemini 3.1 Flash Lite", "latest & fastest"),
                Option("gemini-2.5-pro", "Gemini 2.5 Pro", "most capable"),
                Option("gemini-2.5-flash", "Gemini 2.5 Flash", "fast & efficient"),
                Option("gemini-2.5-flash-lite", "Gemini 2.5 Flash Lite", "fastest"),
            ]
        case .openclaw:
            [Option("default", "Default model")]
        case .agy:
            [
                Option("Gemini 3.8 Flash", "Gemini 3.8 Flash"),
                Option("Claude Sonnet 4.6 (Thinking)", "Claude Sonnet 4.6 (Thinking)"),
                Option("Claude Opus 4.6 (Thinking)", "Claude Opus 4.6 (Thinking)"),
                Option("GPT-OSS 120B (Medium)", "GPT-OSS 120B (Medium)"),
            ]
        case .opencode:
            OpenCode.models
        }
    }

    /// The model rows Settings › Agents lists: the catalog plus a saved model
    /// that left it (`includeConfiguredModel`), without the `default` row.
    public static func modelModes(_ agent: Agent, configured: String?) -> [Option] {
        var models = hardcodedModels(agent)
        let key = agent == .claude ? configured.map { retiredClaudeModelModes[$0] ?? $0 } : configured
        if agent == .claude || agent == .codex || agent == .agy,
           let key, key != "default", !models.contains(where: { $0.key == key }) {
            let name = agent == .claude ? humanizeClaudeModelKey(key) : key
            models.append(Option(key, name, agent == .codex ? "custom model" : "saved model"))
        }
        return models.filter { $0.key != "default" }
    }

    /// Effort levels per model: one scale for Claude, Codex per model.
    public static func effortLevels(_ agent: Agent, model: String) -> [Option] {
        let keys: [String]
        switch agent {
        case .claude:
            keys = ["low", "medium", "high", "xhigh", "max"]
        case .codex:
            let byModel: [String: [String]] = [
                "gpt-6-astra": ["low", "medium", "high", "xhigh", "max", "ultra"],
                "gpt-6.1-sol": ["low", "medium", "high", "xhigh", "max", "ultra"],
                "gpt-6-sol": ["low", "medium", "high", "xhigh", "max", "ultra"],
                "gpt-6-luna": ["low", "medium", "high", "xhigh", "max"],
                "gpt-5.6-sol": ["low", "medium", "high", "xhigh", "max", "ultra"],
                "gpt-5.6-terra": ["low", "medium", "high", "xhigh", "max", "ultra"],
                "gpt-5.6-luna": ["low", "medium", "high", "xhigh", "max"],
            ]
            keys = byModel[model] ?? ["low", "medium", "high", "xhigh"]
        case .agy:
            keys = model == "Gemini 3.8 Flash" ? ["low", "medium", "high"] : []
        case .gemini, .openclaw, .opencode:
            keys = []
        }
        return keys.map { Option($0, $0 == "xhigh" ? "xHigh" : $0.prefix(1).uppercased() + $0.dropFirst()) }
    }

    /// `optionName`: an option's name, the raw key if unlisted, or "none".
    public static func optionName(_ options: [Option], _ key: String?) -> String {
        guard let key, !key.isEmpty else { return "none" }
        return options.first(where: { $0.key == key })?.name ?? key
    }
}

/// utils/versionUtils.ts: semver comparison with prerelease ordering.
public enum SemanticVersion {
    public static func isWellFormed(_ version: String) -> Bool {
        version.wholeMatch(of: /[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?/) != nil
    }

    /// -1, 0 or 1.
    public static func compare(_ lhs: String, _ rhs: String) -> Int {
        let a = String(lhs.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        let b = String(rhs.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        let core = compareCore(a, b)
        if core != 0 { return core }
        let preA = a.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().first.map(String.init) ?? ""
        let preB = b.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().first.map(String.init) ?? ""
        if preA.isEmpty && preB.isEmpty { return 0 }
        if preA.isEmpty { return 1 }
        if preB.isEmpty { return -1 }
        let segmentsA = preA.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let segmentsB = preB.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        for index in 0..<max(segmentsA.count, segmentsB.count) {
            guard index < segmentsA.count else { return -1 }
            guard index < segmentsB.count else { return 1 }
            let x = segmentsA[index]
            let y = segmentsB[index]
            let xNumeric = !x.isEmpty && x.allSatisfy(\.isNumber)
            let yNumeric = !y.isEmpty && y.allSatisfy(\.isNumber)
            if xNumeric && yNumeric {
                let xTrim = trimZeros(x)
                let yTrim = trimZeros(y)
                if xTrim.count != yTrim.count { return xTrim.count < yTrim.count ? -1 : 1 }
                if xTrim != yTrim { return xTrim < yTrim ? -1 : 1 }
            } else if xNumeric != yNumeric {
                return xNumeric ? -1 : 1
            } else if x != y {
                return x < y ? -1 : 1
            }
        }
        return 0
    }

    private static func compareCore(_ a: String, _ b: String) -> Int {
        func numbers(_ version: String) -> [Int] {
            let core = version.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            return core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        }
        var x = numbers(a)
        var y = numbers(b)
        let length = max(x.count, y.count)
        x += Array(repeating: 0, count: length - x.count)
        y += Array(repeating: 0, count: length - y.count)
        for (p, q) in zip(x, y) where p != q {
            return p < q ? -1 : 1
        }
        return 0
    }

    private static func trimZeros(_ digits: String) -> String {
        let trimmed = digits.drop(while: { $0 == "0" })
        return trimmed.isEmpty ? "0" : String(trimmed)
    }
}
