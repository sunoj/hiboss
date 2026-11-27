// Verifies which Today decision is the full card and that the card's long details collapse.
// Exports: TodayDecisionFocusTests (logic and ImageRenderer only; opens no windows).
// Dependencies: XCTest, HibossKit AttentionItem, and the production Today views.

import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class TodayDecisionFocusTests: XCTestCase {
    private let decisions = ["a", "b", "c"].map {
        AttentionItem(message: AttentionTestSupport.ask(id: MessageID(rawValue: $0), options: ["Ship", "Wait"]),
            group: .priority)
    }

    func testFirstDecisionIsTheFocusWithoutASelection() {
        XCTAssertEqual(TodayDecisionFocus.focusID(decisions, selection: nil), "a")
        XCTAssertNil(TodayDecisionFocus.focusID([], selection: "a"))
    }

    func testSelectionExpandsInPlaceAndFallsBackWhenItLeaves() {
        XCTAssertEqual(TodayDecisionFocus.focusID(decisions, selection: "c"), "c")
        XCTAssertEqual(TodayDecisionFocus.focusID(decisions, selection: "answered"), "a",
            "An answered selection hands the focus back to the first decision")
    }

    func testCardColumnFitsMoreTextPerLineThanTheIsland() {
        let paragraph = String(repeating: "word ", count: 40)
        XCTAssertTrue(OptionDetailsPolicy.isLong(paragraph))
        XCTAssertFalse(OptionDetailsPolicy.isLong(paragraph,
            unitsPerLine: TodayDecisionCard.detailsUnitsPerLine))
    }

    func testRowIsShorterThanTheFocusCard() throws {
        let item = decisions[0]
        let row = try height(TodayDecisionRow(item: item, now: .now, onAnswer: {}))
        let card = try height(TodayDecisionCard(item: item, now: .now, isSubmitting: false, error: nil,
            onSelect: {}, onChoose: { _ in }))
        XCTAssertLessThan(row, 60, "one-line row grew to \(row)")
        XCTAssertLessThan(row, card)
    }

    private func height(_ view: some View) throws -> CGFloat {
        let renderer = ImageRenderer(content: view.frame(width: 640))
        return try XCTUnwrap(renderer.nsImage).size.height
    }
}
