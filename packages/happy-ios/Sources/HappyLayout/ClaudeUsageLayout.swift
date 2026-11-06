import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The usage pill in the home header (UsagePill.tsx `pill`): a dot, 6, the
/// words, in a capsule 10 across and 5 down.
public struct UsagePillLayout: Equatable, Sendable {
    public enum Metrics {
        public static let paddingX: CGFloat = 10
        public static let paddingY: CGFloat = 5
        public static let dotSize: CGFloat = 6
        public static let dotGap: CGFloat = 6
        /// The longest reason ("Anthropic account not connected") is cut
        /// here, so the bar's status title keeps its room.
        public static let maxTextWidth: CGFloat = 120
    }

    public var size: CGSize
    public var dot: CGRect
    public var text: CGRect
    public var cornerRadius: CGFloat { size.height / 2 }

    public init(text measured: CGSize) {
        typealias M = Metrics
        let text = CGSize(width: min(measured.width, M.maxTextWidth), height: measured.height)
        let inner = max(M.dotSize, text.height)
        let height = inner + 2 * M.paddingY
        let mid = height / 2
        dot = CGRect(x: M.paddingX, y: mid - M.dotSize / 2, width: M.dotSize, height: M.dotSize)
        self.text = CGRect(x: dot.maxX + M.dotGap, y: mid - text.height / 2, width: text.width, height: text.height)
        size = CGSize(width: self.text.maxX + M.paddingX, height: height)
    }
}

/// The usage sheet's body (UsagePill.tsx `UsageSheet`), under its bar's
/// "Claude usage": the subtitle, a hairline, then each window's label and
/// percentage on one line, its bar 8 under them and its detail 6 under that.
///
///     |20| Anthropic account-wide
///     ───────────────────────────── (hairline, 12 under the subtitle)
///     |20| Session (5h) ………………… 42% |20|   12 + 12 above the first
///     |20| ████████░░░░░░░░░░░░░░░░ |20|   6 tall, 8 under the line
///     |20| Resets in 3h 12m              6 under the bar
public struct UsageSheetLayout: Equatable, Sendable {
    public enum Metrics {
        public static let paddingX: CGFloat = 20
        public static let subtitleTop: CGFloat = 12
        public static let headerBottom: CGFloat = 12
        public static let listPaddingY: CGFloat = 12
        public static let sectionPaddingY: CGFloat = 12
        public static let barGap: CGFloat = 8
        public static let barHeight: CGFloat = 6
        public static let detailGap: CGFloat = 6
        public static let percentGap: CGFloat = 8
    }

    public struct Input {
        public var label: Measurable
        public var percent: Measurable
        public var detail: Measurable

        public init(label: Measurable, percent: Measurable, detail: Measurable) {
            self.label = label
            self.percent = percent
            self.detail = detail
        }
    }

    public struct Section: Equatable, Sendable {
        public var label: CGRect
        public var percent: CGRect
        public var track: CGRect
        public var detail: CGRect

        /// The bar's fill for `fraction` (0 to 1) of the track.
        public func fill(_ fraction: Double) -> CGRect {
            let share = CGFloat(min(max(fraction, 0), 1))
            return CGRect(x: track.minX, y: track.minY, width: track.width * share, height: track.height)
        }
    }

    public var subtitle: CGRect
    public var divider: CGRect
    public var sections: [Section]
    public var contentHeight: CGFloat

    /// `top` is where the body starts (under the bar), `hairline` one
    /// device pixel.
    public init(width: CGFloat, top: CGFloat, hairline: CGFloat, subtitle: Measurable, sections: [Input]) {
        typealias M = Metrics
        let width = max(0, width)
        let column = max(0, width - 2 * M.paddingX)
        let subtitleSize = subtitle.size(fitting: column)
        self.subtitle = CGRect(x: M.paddingX, y: top + M.subtitleTop, width: subtitleSize.width, height: subtitleSize.height)
        divider = CGRect(x: 0, y: self.subtitle.maxY + M.headerBottom, width: width, height: hairline)
        var y = divider.maxY + M.listPaddingY
        var laid: [Section] = []
        for input in sections {
            y += M.sectionPaddingY
            let percent = input.percent.size(fitting: column)
            let label = input.label.size(fitting: max(0, column - percent.width - M.percentGap))
            let line = max(percent.height, label.height)
            let percentFrame = CGRect(x: width - M.paddingX - percent.width, y: y + line - percent.height, width: percent.width, height: percent.height)
            let labelFrame = CGRect(x: M.paddingX, y: y + line - label.height, width: label.width, height: label.height)
            let track = CGRect(x: M.paddingX, y: y + line + M.barGap, width: column, height: M.barHeight)
            let detail = input.detail.size(fitting: column)
            let detailFrame = CGRect(x: M.paddingX, y: track.maxY + M.detailGap, width: detail.width, height: detail.height)
            laid.append(Section(label: labelFrame, percent: percentFrame, track: track, detail: detailFrame))
            y = detailFrame.maxY + M.sectionPaddingY
        }
        self.sections = laid
        contentHeight = y + M.listPaddingY
    }
}

/// The connection error screen (connection-error.tsx): the details in a
/// card as long as they are, the hint 24 under it, all of it scrolling.
public struct ConnectionErrorLayout: Equatable, Sendable {
    public enum Metrics {
        public static let margin: CGFloat = 16
        public static let radius: CGFloat = 16
        public static let padding: CGFloat = 16
        public static let hintGap: CGFloat = 24
        public static let bottom: CGFloat = 24
    }

    /// In the scroll view's content.
    public var card: CGRect
    /// In the card.
    public var details: CGRect
    public var hint: CGRect
    public var contentSize: CGSize

    public init(width: CGFloat, safeArea: LayoutInsets, details: Measurable, hint: Measurable) {
        typealias M = Metrics
        let width = max(0, width)
        let cardWidth = max(0, width - safeArea.left - safeArea.right - 2 * M.margin)
        let textWidth = max(0, cardWidth - 2 * M.padding)
        let detailsSize = details.size(fitting: textWidth)
        card = CGRect(x: safeArea.left + M.margin, y: M.margin, width: cardWidth, height: detailsSize.height + 2 * M.padding)
        self.details = CGRect(x: M.padding, y: M.padding, width: textWidth, height: detailsSize.height)
        let hintSize = hint.size(fitting: cardWidth)
        self.hint = CGRect(x: card.minX, y: card.maxY + M.hintGap, width: hintSize.width, height: hintSize.height)
        contentSize = CGSize(width: width, height: self.hint.maxY + M.bottom + safeArea.bottom)
    }
}
