// Verifies live geometry preference reduction without creating hosted views or windows.
// Exports: OptionNaturalHeightTests for inactive ViewThatFits branches and measured parts.
// Dependencies: XCTest and the option surface preference keys.

import XCTest
@testable import HibossIsland

final class OptionNaturalHeightTests: XCTestCase {
    func testEmptyBranchCannotEraseVisibleQuestionBounds() {
        let visible = CGRect(x: 18, y: 60, width: 200, height: 20)
        var frame = QuestionTextBounds.defaultValue
        QuestionTextBounds.reduce(value: &frame) { visible }
        QuestionTextBounds.reduce(value: &frame) { .zero }
        XCTAssertEqual(frame, visible)
    }

    func testLaterVisibleQuestionBoundsReplaceEarlierLayout() {
        var frame = CGRect(x: 18, y: 60, width: 200, height: 20)
        let updated = CGRect(x: 18, y: 72, width: 200, height: 20)
        QuestionTextBounds.reduce(value: &frame) { updated }
        XCTAssertEqual(frame, updated)
    }

    func testNaturalPartsMergeAndReplaceWithoutAccumulatingRefreshes() {
        var parts = OptionNaturalHeights.defaultValue
        let header = CGSize(width: 384, height: 40)
        let question = CGSize(width: 384, height: 20)
        OptionNaturalHeights.reduce(value: &parts) { [.header: header] }
        OptionNaturalHeights.reduce(value: &parts) { [.question: question] }
        OptionNaturalHeights.reduce(value: &parts) { [.header: header] }
        XCTAssertEqual(parts, [.header: header, .question: question])
    }
}
