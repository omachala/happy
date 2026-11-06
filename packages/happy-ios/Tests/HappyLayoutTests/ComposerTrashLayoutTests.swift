import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import HappyLayout
import XCTest

/// A Happy CLI chat's trash: add's size, after add, before the chips.
final class ComposerTrashLayoutTests: XCTestCase {
    private func card(showsAdd: Bool = true, showsTrash: Bool, zenMode: Bool = false, compact: Bool = false) -> AgentInputCardLayout {
        AgentInputCardLayout(.init(
            width: 377,
            textContentHeight: 30,
            hasText: true,
            showsAdd: showsAdd,
            model: AgentInputCardLayout.Chip(labelSize: CGSize(width: 80, height: 17)),
            effort: AgentInputCardLayout.Chip(labelSize: CGSize(width: 40, height: 17)),
            separator: CGSize(width: 5, height: 17),
            zenMode: zenMode,
            compact: compact,
            showsTrash: showsTrash
        ))
    }

    /// [+] 2 [trash] 2 [ ·spacer· model · effort ] 2 8 [send]
    func testTheTrashStandsAfterAdd() {
        let layout = card(showsTrash: true)
        assertFrame(layout.add, rect(10, 52, 42, 42))
        assertFrame(layout.trash, rect(54, 52, 42, 42))
        assertFrame(layout.middle, rect(98, 52, 217, 42))
        assertFrame(layout.primary, rect(325, 52, 42, 42))
        let content = layout.middleContent
        XCTAssertNil(content.permission)
        // The spacer takes the 46 left over; 12 + 80 + 4.
        assertFrame(content.model?.frame, rect(48, 1, 96, 40))
        assertFrame(content.separator, rect(146, 12.5, 5, 17))
        assertFrame(content.effort?.frame, rect(153, 1, 64, 40))
        XCTAssertEqual(content.effort?.frame.maxX, layout.middle.width)
        // The card is no taller for it.
        XCTAssertEqual(layout.size, card(showsTrash: false).size)
    }

    func testWithoutAddTheTrashLeadsTheRow() {
        let layout = card(showsAdd: false, showsTrash: true)
        XCTAssertNil(layout.add)
        assertFrame(layout.trash, rect(10, 52, 42, 42))
        assertFrame(layout.middle, rect(54, 52, 261, 42))
    }

    func testNoTrashLeavesTheRowAsItWas() {
        let layout = card(showsTrash: false)
        XCTAssertNil(layout.trash)
        assertFrame(layout.middle, rect(54, 52, 261, 42))
    }

    func testZenModeAndTheCompactCardHaveNoTrash() {
        XCTAssertNil(card(showsTrash: true, zenMode: true).trash)
        XCTAssertEqual(card(showsTrash: true, zenMode: true).middle, card(showsTrash: false, zenMode: true).middle)
        let compact = card(showsTrash: true, compact: true)
        XCTAssertNil(compact.trash)
        XCTAssertEqual(compact.inputContainer, card(showsTrash: false, compact: true).inputContainer)
    }
}
