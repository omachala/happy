import Foundation
import HappyStore

/// What the signed-in home shows, from happy-app's app/(app)/index.tsx
/// (`shouldShowFirstRunInstall`) and SessionsListWrapper.tsx
/// (`resolveHomeEmptyState`):
///   - sessions on screen win: an account with sessions lists them even
///     while every computer is offline;
///   - otherwise no computer means Link Your Computer, and none reachable
///     means the offline checklist;
///   - a reachable computer with nothing listed is "No sessions yet",
///     unless there is an archive to open.
public enum HomeState: Equatable, Sendable {
    /// Machines have never been fetched for this account. An empty store
    /// says nothing yet, so this must not fall through to `link`: an
    /// account restored from another phone has computers.
    case loading
    /// No computer linked: Link Your Computer.
    case link
    /// Computers linked, none reachable, nothing listed: the offline
    /// checklist.
    case offline([MachineChoice], hasArchived: Bool)
    /// A computer is reachable and there are no sessions at all.
    case noSessions
    /// The session list. `offline` is set when every computer is offline,
    /// for the plaque above the list.
    case list(SessionList, offline: [MachineChoice]?)

    /// `machineSections` builds the fork's home (`LegacyMachineHome`) in
    /// place of the flat or project list.
    public init(_ snapshot: LegacyHomeSnapshot, clock: SessionList.Clock = SessionList.Clock(), unknownMachine: String = ProjectHomeData.unknownMachineText, machineSections: MachineSections? = nil) {
        let machines = snapshot.machines
        // Stored machines are worth showing even before the first full
        // fetch (a live `new-machine` can land first); none are not.
        guard machines.synced || !machines.machines.isEmpty else {
            self = .loading
            return
        }
        let choices = MachineChoice.collect(machines.machines)
        let list = machineSections.map {
            SessionList(machineSections: snapshot, fallbackTitles: $0.fallbackTitles, words: .init(unknownMachine: unknownMachine, home: $0.home))
        } ?? SessionList(snapshot, clock: clock, unknownMachine: unknownMachine)
        let offline = !choices.isEmpty && !choices.contains(where: \.online) ? choices : nil
        if list.visibleCount > 0 {
            self = .list(list, offline: offline)
        } else if choices.isEmpty {
            self = .link
        } else if let offline {
            self = .offline(offline, hasArchived: list.hasArchived)
        } else if list.hasArchived {
            self = .list(list, offline: nil)
        } else {
            self = .noSessions
        }
    }

    /// What the fork's home needs beside the snapshot.
    public struct MachineSections: Equatable, Sendable {
        /// First prompts, as titles, for chats the agent hasn't named.
        public var fallbackTitles: [String: String]
        /// `common.home` in the screens' language.
        public var home: String

        public init(fallbackTitles: [String: String] = [:], home: String = "Home") {
            self.fallbackTitles = fallbackTitles
            self.home = home
        }
    }

    /// Home with only machines known, as the first-run screens decide it.
    public init(_ machines: MachinesSnapshot) {
        self.init(LegacyHomeSnapshot(machines: machines, sessions: []))
    }
}

extension AccountSession {
    /// Calls `onChange` with the home state now and whenever anything it is
    /// built from changes.
    @MainActor
    public func observeHome(onChange: @escaping @MainActor (HomeState) -> Void) -> StoreObservation {
        store.observeHome { onChange(HomeState($0)) }
    }
}
