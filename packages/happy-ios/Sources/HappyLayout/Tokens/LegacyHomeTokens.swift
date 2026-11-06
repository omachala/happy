import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// The fork's Happy CLI home (ActiveSessionsGroupCompact.tsx, MainView.tsx,
// UsagePill.tsx, connection-error.tsx): its type and the colours it
// hard-codes. Status colours read the same in light and dark, as the fork
// draws them.

extension Palette {
    /// A session tile's dot (`STATUS_COLOR`): unread and thinking blue,
    /// waiting on a permission orange, online green, offline grey.
    public static let legacyHomeDotBlue = ColorToken("#007AFF")
    public static let legacyHomeDotOrange = ColorToken("#FF9500")
    public static let legacyHomeDotGreen = ColorToken("#34C759")
    public static let legacyHomeDotGrey = ColorToken("#999999")

    /// The usage pill's and sheet's buckets (`pctColor`), and the pill's
    /// dot before a number.
    public static let claudeUsageLow = ColorToken("#34C759")
    public static let claudeUsageMedium = ColorToken("#FF9500")
    public static let claudeUsageHigh = ColorToken("#FF3B30")
    public static let claudeUsagePending = ColorToken("#8E8E93")
    /// The pill's ground (`surfaceHigh`) and the bars' track (`divider`).
    public static let claudeUsagePillGround = surfaceHigh
    public static let claudeUsageTrack = ColorToken("#eaeaea", "#292929")
}

extension TextStyles {
    /// A computer's heading: 17 semibold.
    public static let legacyMachineName = TextStyle(.semiBold, size: 17, lineHeight: 22, letterSpacing: -0.2)
    /// A tile's project name: 17, semibold while unread.
    public static let legacyTileTitle = TextStyle(.regular, size: 17, lineHeight: 22, letterSpacing: -0.1)
    public static let legacyTileTitleUnread = TextStyle(.semiBold, size: 17, lineHeight: 22, letterSpacing: -0.1)
    /// The chat's name under it: 12, semibold while unread.
    public static let legacyTileSubtitle = TextStyle(.regular, size: 12, lineHeight: 16)
    public static let legacyTileSubtitleUnread = TextStyle(.semiBold, size: 12, lineHeight: 16)
    /// The worktree badge's name: 11.
    public static let legacyWorktreeBadge = TextStyle(.regular, size: 11, lineHeight: 14)

    /// The header's connection status: 12 on a 16 line.
    public static let legacyConnectionStatus = TextStyle(.regular, size: 12, lineHeight: 16)
    /// The usage pill: 12 semibold.
    public static let usagePill = TextStyle(.semiBold, size: 12, lineHeight: 16)

    /// The usage sheet (UsagePill.tsx `UsageSheet`).
    public static let usageSheetSubtitle = TextStyle(.regular, size: 13, lineHeight: 18)
    public static let usageSheetLabel = TextStyle(.regular, size: 14, lineHeight: 20)
    public static let usageSheetPercent = TextStyle(.semiBold, size: 16, lineHeight: 20)
    public static let usageSheetDetail = TextStyle(.regular, size: 12, lineHeight: 16)

    /// The connection error's details, monospaced, and the hint under them.
    public static let connectionDiagnostics = TextStyle(.mono, size: 13, lineHeight: 18)
    public static let connectionDiagnosticsHint = TextStyle(.regular, size: 12, lineHeight: 16)
}
