import Foundation
import HappyCore

extension Strings {
    /// The fork's Happy CLI home: its header (logo, status, usage pill), the
    /// usage sheet and the connection error screen. The usage and error
    /// words are the fork's own, in English as it writes them
    /// (UsagePill.tsx, connection-error.tsx); the rest are happy-app's keys.
    enum LegacyHome {
        /// `common.home`: a project rooted at the home directory.
        static var home: String { localized("common.home", "Home") }
        /// `session.newChat`: a chat with no name yet.
        static var newChat: String { localized("session.newChat", "New chat") }
        /// The logo's label: it opens Settings.
        static var settings: String { Strings.openSettings }
        /// The header's `+`, and a computer's.
        static let newSession = "New session"
        static func newSessionOn(_ machine: String) -> String { "New session on \(machine)" }
        static func openMachine(_ machine: String) -> String { "Open \(machine)" }

        // UsagePill.tsx
        static let usageLoading = "Loading…"
        static let usageTitle = "Claude usage"
        static let usageSubtitle = "Anthropic account-wide"
        static let usageSession = "Session (5h)"
        static let usageWeekly = "Weekly (7d)"
        static let usageExtra = "Extra (monthly)"
        static func resetsIn(_ value: String) -> String { "Resets in \(value)" }
        static let usageLabel = "Claude usage"
        /// The pill's weekly figure, "W 41%".
        static func usageWeeklyFigure(_ percent: Double) -> String { "W \(ClaudeUsageFormat.percent(percent))" }
        /// The pill's spoken value: "session 26%, weekly 41%", or the
        /// session alone when there is no weekly window.
        static func usageSpoken(_ usage: ClaudeUsage) -> String {
            var parts = ["session \(ClaudeUsageFormat.percent(usage.fiveHour.utilization))"]
            if let week = usage.sevenDay { parts.append("weekly \(ClaudeUsageFormat.percent(week.utilization))") }
            return parts.joined(separator: ", ")
        }
        static let usageRefresh = "Fetch Claude usage again"

        // connection-error.tsx
        static let connectionErrorTitle = "Connection Error"
        static let connectionErrorHint = "Tap the copy icon to copy these details, then share them with Claude Code for debugging."
        static let copied = "Copied"
        static let copiedMessage = "Connection error details copied to clipboard."
        static let connectionDetails = "Connection error details"
    }
}
