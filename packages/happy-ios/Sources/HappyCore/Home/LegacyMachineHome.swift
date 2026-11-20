import Foundation
import HappyStore

/// The Happy CLI home as this fork draws it (ActiveSessionsGroupCompact.tsx):
/// only live sessions, one section per computer, always headed, computers
/// A–Z, and one row per session.
///
/// Within a computer, sessions go by latest activity, newest first
/// (`activityAt`: the newest message either side, or when the person last
/// opened or left the chat). A stale session (`isStale`: nothing new for
/// a day, and not unread, working or asking) sits below every other, in
/// the same order, drawn muted. The order moves only with activity, never
/// with presence or `thinking`, so rows don't jump while an agent works.
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
    /// `now` (ms) decides which sessions are stale.
    public init(_ snapshot: LegacyHomeSnapshot, fallbackTitles: [String: String] = [:], words: Words = Words(),
                now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        let machines = Dictionary(snapshot.machines.machines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        struct Listed {
            var row: LegacyMachineSessionRow
            var activityAt: Int64
        }
        var live = snapshot.sessions.filter(Self.isListed).map { session in
            let path = session.metadata?["path"]?.stringValue ?? ""
            let activityAt = Self.activityAt(session, seen: snapshot.activity[session.id])
            let status = LegacyMachineSessionStatus(session)
            return (session, Listed(row: LegacyMachineSessionRow(
                id: session.id,
                projectName: Self.projectName(Self.repoPath(path), homeDir: session.metadata?["homeDir"]?.stringValue, home: words.home),
                worktreeName: Self.worktreeName(path),
                title: session.title ?? fallbackTitles[session.id],
                status: status,
                stale: Self.isStale(status: status, activityAt: activityAt, now: now)
            ), activityAt: activityAt))
        }
        // Fresh before stale, then newest activity first; ties in id order
        // so the list never shuffles.
        live.sort { a, b in
            if a.1.row.stale != b.1.row.stale { return !a.1.row.stale }
            if a.1.activityAt != b.1.activityAt { return a.1.activityAt > b.1.activityAt }
            return a.0.id < b.0.id
        }

        struct Group {
            var machineId: String?
            var name: String
            var sessions: [LegacyMachineSessionRow] = []
        }
        var order: [String?] = []
        var groups: [String?: Group] = [:]
        for (session, listed) in live {
            let machineId = Self.nonEmpty(session.metadata?["machineId"]?.stringValue)
            if groups[machineId] == nil {
                order.append(machineId)
                groups[machineId] = Group(machineId: machineId, name: Self.machineName(machineId.flatMap { machines[$0] }, id: machineId, unknown: words.unknownMachine))
            }
            groups[machineId]?.sessions.append(listed.row)
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
                Section(machineId: group.machineId, name: group.name, sessions: group.sessions)
            }
            .sorted { a, b in
                let byName = Collation.compare(a.name, b.name)
                if byName != .orderedSame { return byName == .orderedAscending }
                return (a.machineId ?? "") < (b.machineId ?? "")
            }
    }

    /// Nothing new this long and the row goes stale.
    public static let staleAfterMs: Int64 = 24 * 60 * 60 * 1000

    /// The latest activity: the newest message either side (the server's
    /// `lastMeaningfulMessageAt` when a CLI stamps it, this device's own
    /// last send, the newest message seen here) or when the person last
    /// opened or left the chat (`seen`, from `LegacyHomeSnapshot.activity`),
    /// whichever is later; creation when there is nothing else.
    static func activityAt(_ session: SessionRecord, seen: Int64?) -> Int64 {
        let stamped = session.metadata?["lastMeaningfulMessageAt"]?.numberValue.map { Int64($0) } ?? 0
        return max(session.createdAt, stamped, session.lastMessageSentAt ?? 0, seen ?? 0)
    }

    /// Stale: idle or offline with nothing new for a day. Unread, working,
    /// or asking for a permission or an answer never is.
    static func isStale(status: LegacyMachineSessionStatus, activityAt: Int64, now: Int64) -> Bool {
        switch status {
        case .unread, .thinking, .permissionRequired: return false
        case .waiting, .disconnected: return now - activityAt > staleAfterMs
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
    /// Nothing new for a day (`LegacyMachineHome.isStale`): below the rest,
    /// muted, with no dot.
    public var stale: Bool

    public var unread: Bool { status == .unread }

    public init(id: String, projectName: String, worktreeName: String? = nil, title: String? = nil, status: LegacyMachineSessionStatus, stale: Bool = false) {
        self.id = id
        self.projectName = projectName
        self.worktreeName = worktreeName
        self.title = title
        self.status = status
        self.stale = stale
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
