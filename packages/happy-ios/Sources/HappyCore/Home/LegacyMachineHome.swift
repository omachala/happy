import Foundation
import HappyStore

/// The Happy CLI home as this fork draws it (ActiveSessionsGroupCompact.tsx):
/// only live sessions, one section per computer, always headed, computers
/// A–Z, and one row per session.
///
/// Within a computer, sessions group by project (the repository a
/// `/.dev/worktree/<name>` checkout belongs to) in the order of each
/// project's newest session, newest session first inside a project; the
/// groups are then flattened into one card. "Newest" is creation time, or
/// the last activity when the synced `sortSessionsByActivity` is on.
///
/// Pure and off the main thread; the words it can't know (`<unknown>`,
/// "Home") are handed in, read in the screens' language on the main thread.
public struct LegacyMachineHome: Equatable, Sendable {
    public struct Section: Equatable, Sendable {
        /// Nil for sessions that name no computer.
        public var machineId: String?
        public var name: String
        public var sessions: [LegacyMachineSessionRow]
    }

    /// The words the screens supply.
    public struct Words: Equatable, Sendable {
        /// `status.unknown`, drawn as `<unknown>`.
        public var unknownMachine: String
        /// `common.home`, a project rooted at the home directory.
        public var home: String

        public init(unknownMachine: String = ProjectHomeData.unknownMachineText, home: String = "Home") {
            self.unknownMachine = unknownMachine
            self.home = home
        }
    }

    public var sections: [Section]
    /// Each computer's first known folder (`machineId` to path).
    public var firstPaths: [String: String] = [:]

    public var sessionCount: Int { sections.reduce(0) { $0 + $1.sessions.count } }

    /// `fallbackTitles` are the chats' first prompts, already made titles
    /// (`LegacyFirstPrompts`), for chats the agent hasn't named.
    public init(_ snapshot: LegacyHomeSnapshot, fallbackTitles: [String: String] = [:], words: Words = Words()) {
        // Only an explicit synced value counts: the fork's default is
        // creation order, while AccountSettings defaults this key to true.
        var stored = snapshot.settings.synced?.settings?.objectValue ?? [:]
        stored.merge(snapshot.settings.pending) { _, pending in pending }
        let byActivity = stored["sortSessionsByActivity"]?.boolValue ?? false
        let machines = Dictionary(snapshot.machines.machines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var live = snapshot.sessions.filter(Self.isListed)
        // The store's active list: newest first; ties in id order so the
        // list never shuffles.
        live.sort { a, b in
            let keyA = byActivity ? a.lastActivityAt : a.createdAt
            let keyB = byActivity ? b.lastActivityAt : b.createdAt
            if keyA != keyB { return keyA > keyB }
            return a.id < b.id
        }

        struct Group {
            var machineId: String?
            var name: String
            var projectOrder: [String] = []
            var projects: [String: [LegacyMachineSessionRow]] = [:]
        }
        var order: [String?] = []
        var groups: [String?: Group] = [:]
        for session in live {
            let metadata = session.metadata
            let machineId = Self.nonEmpty(metadata?["machineId"]?.stringValue)
            if groups[machineId] == nil {
                order.append(machineId)
                groups[machineId] = Group(machineId: machineId, name: Self.machineName(machineId.flatMap { machines[$0] }, id: machineId, unknown: words.unknownMachine))
            }
            let path = metadata?["path"]?.stringValue ?? ""
            let project = Self.repoPath(path)
            let row = LegacyMachineSessionRow(
                id: session.id,
                projectName: Self.projectName(project, homeDir: metadata?["homeDir"]?.stringValue, home: words.home),
                worktreeName: Self.worktreeName(path),
                title: session.title ?? fallbackTitles[session.id],
                status: LegacyMachineSessionStatus(session)
            )
            if groups[machineId]?.projects[project] == nil { groups[machineId]?.projectOrder.append(project) }
            groups[machineId]?.projects[project, default: []].append(row)
        }

        // new/index.tsx `pathItems`: every folder a session of that computer
        // ran in (live or not), sorted; the first is where its `+` starts.
        var paths: [String: Set<String>] = [:]
        for session in snapshot.sessions {
            guard let machineId = Self.nonEmpty(session.metadata?["machineId"]?.stringValue),
                  let path = Self.nonEmpty(session.metadata?["path"]?.stringValue) else { continue }
            paths[machineId, default: []].insert(path)
        }
        firstPaths = paths.mapValues { $0.min()! }

        sections = order.compactMap { groups[$0] }
            .map { group in
                Section(machineId: group.machineId, name: group.name, sessions: group.projectOrder.flatMap { group.projects[$0] ?? [] })
            }
            .sorted { a, b in
                let byName = Collation.compare(a.name, b.name)
                if byName != .orderedSame { return byName == .orderedAscending }
                return (a.machineId ?? "") < (b.machineId ?? "")
            }
    }

    /// `session.active === true`: running and not archived (or being
    /// archived from here). Side chats and retired tasks never list.
    static func isListed(_ session: SessionRecord) -> Bool {
        session.active && !session.isArchived && !session.isRetiredTask
            && session.metadata?["isSideChat"]?.boolValue != true
    }

    /// `displayName || host || machineId`, or `<unknown>`.
    static func machineName(_ machine: MachineRecord?, id: String?, unknown: String) -> String {
        nonEmpty(machine?.metadata?["displayName"]?.stringValue)
            ?? nonEmpty(machine?.metadata?["host"]?.stringValue)
            ?? id
            ?? "<\(unknown)>"
    }

    /// utils/worktree.ts `WORKTREE_PATH_MARKER`.
    static let worktreeMarker = "/.dev/worktree/"

    /// utils/worktree.ts `getRepoPath`: a worktree's repository.
    public static func repoPath(_ path: String) -> String {
        guard let marker = path.range(of: worktreeMarker) else { return path }
        return String(path[..<marker.lowerBound])
    }

    /// utils/worktree.ts `getWorktreeName`; nil outside a worktree.
    public static func worktreeName(_ path: String) -> String? {
        guard let marker = path.range(of: worktreeMarker) else { return nil }
        return String(path[marker.upperBound...])
    }

    /// The last segment of the path relative to home, first letter capital;
    /// the home directory itself is `home`.
    public static func projectName(_ projectPath: String, homeDir: String?, home: String) -> String {
        let display = NewSessionChoices.relativeToHome(projectPath, homeDir: homeDir)
        let segments = display.split(whereSeparator: { $0 == "/" || $0 == "\\" })
        let raw = segments.last.map(String.init) ?? display
        if raw == "~" { return home }
        guard let first = raw.first else { return raw }
        return first.uppercased() + raw.dropFirst()
    }

    /// sessionUtils.ts `deriveTitleFromText`: whitespace collapsed to single
    /// spaces, at most 80 characters and an ellipsis.
    public static func title(fromText text: String) -> String {
        let collapsed = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        guard collapsed.count > 80 else { return collapsed }
        var cut = String(collapsed.prefix(80))
        while let last = cut.last, last.isWhitespace { cut.removeLast() }
        return cut + "…"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    // MARK: Rows

    /// The list as it is drawn: each computer's heading, then its sessions.
    public var rows: [LegacyMachineHomeRow] {
        sections.enumerated().flatMap { index, section in
            [LegacyMachineHomeRow.machine(LegacyMachineHeader(
                machineId: section.machineId, name: section.name, first: index == 0,
                firstPath: section.machineId.flatMap { firstPaths[$0] }
            ))]
                + section.sessions.map(LegacyMachineHomeRow.session)
        }
    }
}

/// The session tile's dot (ActiveSessionsGroupCompact.tsx `STATUS_COLOR`).
public enum LegacyMachineSessionStatus: Equatable, Sendable {
    /// A turn ended, or the agent asks, with nobody looking: solid blue.
    case unread
    /// Blue, pulsing.
    case thinking
    /// Orange, pulsing.
    case permissionRequired
    /// Online and idle: green.
    case waiting
    /// Not online: grey.
    case disconnected

    /// Unread wins over every state.
    public init(_ session: SessionRecord) {
        if session.unread {
            self = .unread
            return
        }
        switch SessionState(session) {
        case .disconnected: self = .disconnected
        case .permissionRequired, .inputRequired: self = .permissionRequired
        case .thinking: self = .thinking
        case .waiting: self = .waiting
        }
    }

    public var pulses: Bool { self == .thinking || self == .permissionRequired }
}

/// One session's tile.
public struct LegacyMachineSessionRow: Equatable, Sendable {
    public var id: String
    /// The project's folder, repeated for sibling sessions.
    public var projectName: String
    /// The worktree's name, beside the branch glyph.
    public var worktreeName: String?
    /// The chat's name; nil reads "New chat".
    public var title: String?
    public var status: LegacyMachineSessionStatus

    public var unread: Bool { status == .unread }

    public init(id: String, projectName: String, worktreeName: String? = nil, title: String? = nil, status: LegacyMachineSessionStatus) {
        self.id = id
        self.projectName = projectName
        self.worktreeName = worktreeName
        self.title = title
        self.status = status
    }
}

/// A computer heading its section: a tap opens the computer (not the
/// unknown one); its `+` starts a session there.
public struct LegacyMachineHeader: Equatable, Sendable {
    public var machineId: String?
    public var name: String
    /// The list's first heading, which sits closer to the top.
    public var first: Bool
    /// Where its `+` starts the new session: the alphabetically first
    /// folder any session of this computer ran in (new/index.tsx picks it
    /// when the draft's path is cleared); nil for home.
    public var firstPath: String?

    public init(machineId: String?, name: String, first: Bool = false, firstPath: String? = nil) {
        self.machineId = machineId
        self.name = name
        self.first = first
        self.firstPath = firstPath
    }
}

public enum LegacyMachineHomeRow: Equatable, Sendable {
    case machine(LegacyMachineHeader)
    case session(LegacyMachineSessionRow)
}
