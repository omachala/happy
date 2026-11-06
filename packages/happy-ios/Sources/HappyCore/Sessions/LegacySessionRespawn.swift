import Foundation
import HappyStore
import HappyWire

/// The composer's trash (the fork's SessionView.tsx `onClear`): the chat's
/// agent is stopped and a fresh one starts in the same directory on the
/// same computer, with the same harness, model and permission picks. No
/// confirmation; the screen puts the new chat in the old one's place.
///
/// Happy CLI sessions only: Happy Agent's sessions are started through
/// their own catalog.
public enum LegacySessionRespawn {
    public struct Plan: Equatable, Sendable {
        public var machineId: String
        public var directory: String
        /// `spawn-happy-session`'s `agent`.
        public var agent: String
    }

    public enum Failure: Error, Equatable, Sendable, LocalizedError {
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .failed(let message): message
            }
        }
    }

    /// What the trash does, one step each, so a test can stand in for the
    /// machine and the store.
    public struct Steps: Sendable {
        /// `killSession`; true when the CLI confirmed it stopped.
        public var kill: @Sendable (_ sessionId: String) async -> Bool
        /// Marks it inactive on the server when the CLI couldn't be reached.
        public var archive: @Sendable (_ sessionId: String) async throws -> Void
        public var spawn: @Sendable (SpawnSessionOptions) async -> SpawnSessionResult
        /// The session list, read again so the new session is in the store.
        public var refreshSessions: @Sendable () async -> Void
        /// The old session's permission and model picks onto the new one,
        /// on this phone only (not pushed).
        public var copyPicks: @Sendable (_ from: String, _ to: String) async throws -> Void

        public init(
            kill: @escaping @Sendable (_ sessionId: String) async -> Bool,
            archive: @escaping @Sendable (_ sessionId: String) async throws -> Void,
            spawn: @escaping @Sendable (SpawnSessionOptions) async -> SpawnSessionResult,
            refreshSessions: @escaping @Sendable () async -> Void,
            copyPicks: @escaping @Sendable (_ from: String, _ to: String) async throws -> Void
        ) {
            self.kill = kill
            self.archive = archive
            self.spawn = spawn
            self.refreshSessions = refreshSessions
            self.copyPicks = copyPicks
        }
    }

    /// The fork's agent for a flavor: the ones the daemon knows by name,
    /// Claude for anything else.
    public static func agent(flavor: String?) -> String {
        switch flavor {
        case "codex", "gemini", "openclaw", "agy", "opencode": flavor!
        default: "claude"
        }
    }

    /// Where the new session would start; nil hides the trash. It shows
    /// only while the session is connected and its metadata names the
    /// computer and the directory.
    public static func plan(_ record: SessionRecord?) -> Plan? {
        guard let record, !record.isRig, SessionState(record) != .disconnected else { return nil }
        let metadata = record.metadata
        guard let machineId = metadata?["machineId"]?.stringValue, !machineId.isEmpty,
              let path = metadata?["path"]?.stringValue, !path.isEmpty else { return nil }
        return Plan(machineId: machineId, directory: path, agent: agent(flavor: metadata?["flavor"]?.stringValue))
    }

    /// Stops `sessionId` (or archives it when its CLI can't be reached),
    /// starts its replacement, reads the list again and carries the picks
    /// over. Returns the new session's id.
    public static func run(sessionId: String, plan: Plan, steps: Steps) async throws -> String {
        if !(await steps.kill(sessionId)) {
            try await steps.archive(sessionId)
        }
        let result = await steps.spawn(SpawnSessionOptions(machineId: plan.machineId, directory: plan.directory, agent: plan.agent))
        let newId: String
        switch result {
        case .success(let sessionId):
            newId = sessionId
        case .error(let message):
            throw Failure.failed(message.isEmpty ? defaultMessage : message)
        case .pending, .requestToApproveDirectoryCreation:
            throw Failure.failed(defaultMessage)
        }
        await steps.refreshSessions()
        try await steps.copyPicks(sessionId, newId)
        return newId
    }

    static let defaultMessage = "Failed to start new session"

    /// The account's own: its RPCs, its sync and its store.
    public static func steps(_ account: AccountSession) -> Steps {
        let actions = account.actions
        let machines = account.machineActions
        let sync = account.sync
        let store = account.store
        return Steps(
            kill: { sessionId in
                (try? await actions.sessionKill(sessionId: sessionId).success) ?? false
            },
            archive: { sessionId in
                try await actions.archive(sessionId: sessionId)
            },
            spawn: { options in
                await machines.machineSpawnNewSession(options: options)
            },
            refreshSessions: {
                await sync.run(.sessions)
            },
            copyPicks: { from, to in
                try copyPicks(store: store, from: from, to: to)
            }
        )
    }

    /// `storage.updateSessionAgentModes(newId, permissionMode, modelMode)`:
    /// the effort stays the new session's default.
    static func copyPicks(store: LocalStore, from: String, to: String) throws {
        let old = try store.composerState(sessionId: from).values
        var next = try store.composerState(sessionId: to)
        var values = next.values.objectValue ?? [:]
        for key in ["permissionMode", "modelMode"] {
            if let value = old[key], value != .null { values[key] = value }
        }
        next.values = .object(values)
        try store.saveComposerState(next)
    }
}
