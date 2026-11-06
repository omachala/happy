import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import HappyLayout
import XCTest

/// The fork's Happy CLI home on a 393-wide phone: headings 24 in from the
/// edges (the card's 16 and 8), tiles in 361-wide cards with 20 inside.
final class LegacyMachineHomeLayoutTests: XCTestCase {
    // MARK: Computer heading

    func testAHeadingHasItsGlyphNameAndPlus() {
        let layout = LegacyMachineHeaderLayout(width: 393, first: false, icon: CGSize(width: 14, height: 14), name: text("Studio", lineHeight: 22, maxLines: 1))
        // 24 above; the row is the `+`'s 28; 8 below.
        assertFrame(layout.icon, rect(24, 31, 14, 14))
        assertFrame(layout.name, rect(45, 27, 48, 22))
        assertFrame(layout.add, rect(341, 24, 28, 28))
        assertSize(layout.size, CGSize(width: 393, height: 60))
    }

    func testTheFirstHeadingSitsHigherAndALongNameStopsShortOfThePlus() {
        let layout = LegacyMachineHeaderLayout(width: 393, first: true, icon: CGSize(width: 14, height: 14), name: text(String(repeating: "m", count: 50), lineHeight: 22, maxLines: 1))
        assertFrame(layout.icon, rect(24, 15, 14, 14))
        // 341 - 4 - 45: cut 4 before the `+`.
        assertFrame(layout.name, rect(45, 11, 292, 22))
        assertFrame(layout.add, rect(341, 8, 28, 28))
        assertSize(layout.size, CGSize(width: 393, height: 44))
    }

    // MARK: Session tile

    private let branch = CGSize(width: 11, height: 11)

    func testATileWithItsChatName() {
        let layout = LegacyMachineSessionRowLayout(width: 361, title: text("Happy", lineHeight: 22, maxLines: 1), badge: nil, subtitle: text("Fix the build", lineHeight: 16, maxLines: 1))
        // 22 + 2 + 16 of text, 16 above and below: 72.
        assertFrame(layout.title, rect(20, 16, 40, 22))
        assertFrame(layout.subtitle, rect(20, 40, 104, 16))
        assertFrame(layout.dot, rect(333, 32, 8, 8))
        XCTAssertNil(layout.badge)
        assertSize(layout.size, CGSize(width: 361, height: 72))
    }

    func testAWorktreeBadgeFollowsTheTitleAndOneLineKeepsSixty() {
        let layout = LegacyMachineSessionRowLayout(width: 361, title: text("Happy", lineHeight: 22, maxLines: 1), badge: .init(icon: branch, name: text("swift-ocean", lineHeight: 14, maxLines: 1)), subtitle: nil)
        assertFrame(layout.title, rect(20, 19, 40, 22))
        // 8 after the title: 6, the glyph, 3, the name, 6; 1 above and below.
        assertFrame(layout.badge, rect(68, 22, 114, 16))
        assertFrame(layout.badgeIcon, rect(74, 24.5, 11, 11))
        assertFrame(layout.badgeName, rect(88, 23, 88, 14))
        XCTAssertNil(layout.subtitle)
        assertFrame(layout.dot, rect(333, 26, 8, 8))
        assertSize(layout.size, CGSize(width: 361, height: 60))
    }

    func testATitleAndBadgeTooLongShareTheOverflow() {
        let layout = LegacyMachineSessionRowLayout(width: 361, title: text(String(repeating: "t", count: 30), lineHeight: 22, maxLines: 1), badge: .init(icon: branch, name: text(String(repeating: "b", count: 20), lineHeight: 14, maxLines: 1)), subtitle: nil)
        // 240 + 8 + 186 in a 303 column: 131 over, the badge giving 186/426 of it.
        let badge = 186 - 131.0 * 186 / 426
        assertFrame(layout.title, rect(20, 19, 303 - 8 - badge, 22))
        assertFrame(layout.badge, rect(323 - badge, 22, badge, 16))
        assertFrame(layout.badgeName, rect(323 - badge + 20, 23, badge - 26, 14))
        XCTAssertEqual(layout.badge!.maxX, 323, accuracy: 0.001, "10 before the dot")
    }

    func testABadgeNeverShrinksBelowItsGlyph() {
        let layout = LegacyMachineSessionRowLayout(width: 60, title: text(String(repeating: "t", count: 30), lineHeight: 22, maxLines: 1), badge: .init(icon: branch, name: text(String(repeating: "b", count: 20), lineHeight: 14, maxLines: 1)), subtitle: nil)
        // A 2 column: the badge's share of the overflow would take it under
        // its glyph and padding, so it keeps those 26 and the title nothing.
        assertFrame(layout.title, rect(20, 19, 0, 22))
        assertFrame(layout.badge, rect(28, 22, 26, 16))
        assertFrame(layout.badgeName, rect(48, 23, 0, 14))
    }

    // MARK: Header status and pill

    func testTheStatusWithAndWithoutItsInfoGlyph() {
        let tappable = LegacyConnectionStatusLayout(text: CGSize(width: 72, height: 16), info: CGSize(width: 12, height: 12))
        assertFrame(tappable.dot, rect(0, 5, 6, 6))
        assertFrame(tappable.text, rect(10, 0, 72, 16))
        assertFrame(tappable.info, rect(86, 2, 12, 12))
        assertSize(tappable.size, CGSize(width: 98, height: 16))

        let plain = LegacyConnectionStatusLayout(text: CGSize(width: 72, height: 16), info: nil)
        XCTAssertNil(plain.info)
        assertSize(plain.size, CGSize(width: 82, height: 16))
    }

    func testThePill() {
        let layout = UsagePillLayout(text: CGSize(width: 24, height: 16))
        assertFrame(layout.dot, rect(10, 10, 6, 6))
        assertFrame(layout.text, rect(22, 5, 24, 16))
        assertSize(layout.size, CGSize(width: 56, height: 26))
        XCTAssertEqual(layout.cornerRadius, 13)
    }

    // MARK: Usage sheet

    func testTheSheetStacksItsWindows() {
        let section = UsageSheetLayout.Input(label: text("Session (5h)", lineHeight: 20, maxLines: 1), percent: text("42%", lineHeight: 20, maxLines: 1), detail: text("Resets in 3h", lineHeight: 16, maxLines: 1))
        let layout = UsageSheetLayout(width: 393, top: 56, hairline: 0.5, subtitle: text("Anthropic account-wide", lineHeight: 18), sections: [section, section])
        assertFrame(layout.subtitle, rect(20, 68, 176, 18))
        assertFrame(layout.divider, rect(0, 98, 393, 0.5))
        let first = layout.sections[0]
        assertFrame(first.label, rect(20, 122.5, 96, 20))
        assertFrame(first.percent, rect(349, 122.5, 24, 20))
        assertFrame(first.track, rect(20, 150.5, 353, 6))
        assertFrame(first.detail, rect(20, 162.5, 96, 16))
        assertFrame(layout.sections[1].label, rect(20, 202.5, 96, 20))
        assertFrame(layout.sections[1].track, rect(20, 230.5, 353, 6))
        XCTAssertEqual(layout.contentHeight, 282.5)
        assertFrame(first.fill(0.42), rect(20, 150.5, 353 * 0.42, 6))
        assertFrame(first.fill(1.4), rect(20, 150.5, 353, 6))
        assertFrame(first.fill(-1), rect(20, 150.5, 0, 6))
    }

    // MARK: Connection error

    func testTheDetailsCardAndHintScrollTogether() {
        let layout = ConnectionErrorLayout(width: 393, safeArea: LayoutInsets(), details: text(String(repeating: "x", count: 100), lineHeight: 18), hint: text(String(repeating: "h", count: 20), lineHeight: 16))
        // 329 for the text: 41 characters a line, 3 lines.
        assertFrame(layout.card, rect(16, 16, 361, 86))
        assertFrame(layout.details, rect(16, 16, 329, 54))
        assertFrame(layout.hint, rect(16, 126, 160, 16))
        assertSize(layout.contentSize, CGSize(width: 393, height: 166))
    }
}
