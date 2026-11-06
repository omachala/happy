import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A computer heading its section in the fork's Happy CLI home
/// (ActiveSessionsGroupCompact.tsx `MachineHeader`): the desktop glyph and
/// the name on the left, the `+` at the right, over the section's card.
///
///     |side+8| glyph |7| name ………… |4| [+] |side+8|
///
/// 24 above (8 for the first section, which sits under the list's own
/// top), 8 below to the card.
public struct LegacyMachineHeaderLayout: Equatable, Sendable {
    public enum Metrics {
        public static let paddingX: CGFloat = HomeCardLayout.Metrics.side + 8
        public static let paddingTop: CGFloat = 24
        public static let firstPaddingTop: CGFloat = 8
        public static let paddingBottom: CGFloat = 8
        public static let iconSize: CGFloat = 14
        public static let iconGap: CGFloat = 7
        /// The `+`'s glyph and the box a finger hits around it.
        public static let addIconSize: CGFloat = 20
        public static let addBox = CGSize(width: 28, height: 28)
        public static let addGap: CGFloat = 4
    }

    public var size: CGSize
    public var icon: CGRect
    public var name: CGRect
    public var add: CGRect

    public init(width: CGFloat, first: Bool, icon: CGSize, name: Measurable) {
        typealias M = Metrics
        let width = max(0, width)
        let top = first ? M.firstPaddingTop : M.paddingTop
        let add = M.addBox
        let addX = width - M.paddingX - add.width
        let nameX = M.paddingX + icon.width + M.iconGap
        let nameMax = max(0, addX - M.addGap - nameX)
        let fitted = name.size(fitting: nameMax)
        let text = CGSize(width: min(fitted.width, nameMax), height: fitted.height)
        let rowHeight = max(icon.height, text.height, add.height)
        let midY = top + rowHeight / 2
        self.icon = CGRect(x: M.paddingX, y: midY - icon.height / 2, width: icon.width, height: icon.height)
        self.name = CGRect(x: nameX, y: midY - text.height / 2, width: text.width, height: text.height)
        self.add = CGRect(x: addX, y: midY - add.height / 2, width: add.width, height: add.height)
        size = CGSize(width: width, height: top + rowHeight + M.paddingBottom)
    }
}

/// One session's tile in its computer's card (`SessionTile`), laid out at
/// the card's width (`HomeCardLayout.contentWidth`):
///
///     |20| title |8| (⑂ worktree) ………… |10| ● |20|
///     |20| chat name …………………………………………
///
/// 16 above and below the text, 60 at least. Title and badge share their
/// line and both give way when it is short, each by its share of the
/// overflow, the badge never below its glyph and padding.
public struct LegacyMachineSessionRowLayout: Equatable, Sendable {
    public enum Metrics {
        public static let paddingX: CGFloat = 20
        public static let paddingY: CGFloat = 16
        public static let minHeight: CGFloat = 60
        public static let titleGap: CGFloat = 8
        public static let subtitleGap: CGFloat = 2
        public static let dotSize: CGFloat = 8
        public static let dotGap: CGFloat = 10
        /// The worktree badge: 6 across, 1 down, the glyph 3 from the name.
        public static let badgePaddingX: CGFloat = 6
        public static let badgePaddingY: CGFloat = 1
        public static let badgeIconSize: CGFloat = 11
        public static let badgeIconGap: CGFloat = 3
        public static let badgeRadius: CGFloat = 6
    }

    public struct Badge {
        public var icon: CGSize
        public var name: Measurable

        public init(icon: CGSize, name: Measurable) {
            self.icon = icon
            self.name = name
        }
    }

    public var size: CGSize
    public var title: CGRect
    public var badge: CGRect?
    public var badgeIcon: CGRect?
    public var badgeName: CGRect?
    public var subtitle: CGRect?
    public var dot: CGRect

    public init(width: CGFloat, title: Measurable, badge: Badge?, subtitle: Measurable?) {
        typealias M = Metrics
        let width = max(0, width)
        let dotX = width - M.paddingX - M.dotSize
        let column = max(0, dotX - M.dotGap - M.paddingX)

        let titleSize = title.size(fitting: .greatestFiniteMagnitude)
        var titleWidth = titleSize.width
        var badgeBox: CGSize?
        var badgeNameSize = CGSize.zero
        if let badge {
            badgeNameSize = badge.name.size(fitting: .greatestFiniteMagnitude)
            let inner = badge.icon.width + M.badgeIconGap + badgeNameSize.width
            badgeBox = CGSize(width: inner + 2 * M.badgePaddingX, height: max(badge.icon.height, badgeNameSize.height) + 2 * M.badgePaddingY)
        }
        let natural = titleWidth + (badgeBox.map { M.titleGap + $0.width } ?? 0)
        if natural > column {
            let overflow = natural - column
            if var box = badgeBox, let badge {
                let floor = badge.icon.width + M.badgeIconGap + 2 * M.badgePaddingX
                let total = titleWidth + box.width
                var badgeCut = total > 0 ? overflow * box.width / total : 0
                badgeCut = min(badgeCut, box.width - floor)
                box.width -= max(0, badgeCut)
                titleWidth = max(0, column - M.titleGap - box.width)
                badgeNameSize.width = max(0, box.width - floor)
                badgeBox = box
            } else {
                titleWidth = column
            }
        }

        let lineHeight = max(titleSize.height, badgeBox?.height ?? 0)
        let subtitleSize = subtitle.map { $0.size(fitting: column) }
        let content = lineHeight + (subtitleSize.map { M.subtitleGap + $0.height } ?? 0)
        let height = max(M.minHeight, content + 2 * M.paddingY)
        let top = (height - content) / 2
        let lineMid = top + lineHeight / 2

        self.title = CGRect(x: M.paddingX, y: lineMid - titleSize.height / 2, width: titleWidth, height: titleSize.height)
        if let box = badgeBox, let badge {
            let frame = CGRect(x: self.title.maxX + M.titleGap, y: lineMid - box.height / 2, width: box.width, height: box.height)
            self.badge = frame
            badgeIcon = CGRect(x: frame.minX + M.badgePaddingX, y: lineMid - badge.icon.height / 2, width: badge.icon.width, height: badge.icon.height)
            badgeName = CGRect(x: badgeIcon!.maxX + M.badgeIconGap, y: lineMid - badgeNameSize.height / 2, width: badgeNameSize.width, height: badgeNameSize.height)
        }
        self.subtitle = subtitleSize.map { CGRect(x: M.paddingX, y: top + lineHeight + M.subtitleGap, width: $0.width, height: $0.height) }
        dot = CGRect(x: dotX, y: height / 2 - M.dotSize / 2, width: M.dotSize, height: M.dotSize)
        size = CGSize(width: width, height: height)
    }
}

/// The home header's connection status (MainView.tsx `HeaderTitle`): a dot,
/// 4, the words, and, while a tap opens the details, 4 and an info glyph.
public struct LegacyConnectionStatusLayout: Equatable, Sendable {
    public enum Metrics {
        public static let dotSize: CGFloat = 6
        public static let dotGap: CGFloat = 4
        public static let infoSize: CGFloat = 12
        public static let infoGap: CGFloat = 4
    }

    public var size: CGSize
    public var dot: CGRect
    public var text: CGRect
    public var info: CGRect?

    public init(text: CGSize, info: CGSize?) {
        typealias M = Metrics
        let height = max(M.dotSize, text.height, info?.height ?? 0)
        let mid = height / 2
        dot = CGRect(x: 0, y: mid - M.dotSize / 2, width: M.dotSize, height: M.dotSize)
        let textFrame = CGRect(x: dot.maxX + M.dotGap, y: mid - text.height / 2, width: text.width, height: text.height)
        let infoFrame = info.map { CGRect(x: textFrame.maxX + M.infoGap, y: mid - $0.height / 2, width: $0.width, height: $0.height) }
        self.text = textFrame
        self.info = infoFrame
        size = CGSize(width: (infoFrame ?? textFrame).maxX, height: height)
    }
}
