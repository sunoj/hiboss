// Pure rules behind the catalog v2 native inputs: ranking order and per-item review answers.
// Exports: PanelInputsV2Tests.
// Dependencies: XCTest and HibossKit's RankedChoiceOrder and ItemReviewAnswer.

import XCTest
@testable import HibossKit

final class PanelInputsV2Tests: XCTestCase {
    private let options = ["sync", "settings", "flag"].map { PanelOption(id: $0, label: $0, description: nil) }

    func testOrderFallsBackToTheOptionsUntilAValidRankingIsStored() {
        XCTAssertEqual(RankedChoiceOrder.order(stored: nil, options: options), ["sync", "settings", "flag"])
        XCTAssertEqual(RankedChoiceOrder.order(stored: ["flag"], options: options), ["flag", "sync", "settings"])
        XCTAssertEqual(RankedChoiceOrder.order(stored: ["flag", "flag"], options: options), ["sync", "settings", "flag"])
        XCTAssertEqual(RankedChoiceOrder.order(stored: ["gone"], options: options), ["sync", "settings", "flag"])
    }

    func testMovingSwapsNeighboursAndStopsAtTheEnds() {
        let order = ["sync", "settings", "flag"]
        XCTAssertEqual(RankedChoiceOrder.moved(order, from: 2, by: -1), ["sync", "flag", "settings"])
        XCTAssertEqual(RankedChoiceOrder.moved(order, from: 0, by: -1), order)
        XCTAssertEqual(RankedChoiceOrder.moved(order, from: 2, by: 1), order)
    }

    func testTheAnswerIsTheRankedPrefix() {
        XCTAssertEqual(RankedChoiceOrder.answer(["flag", "sync", "settings"], topK: 2), ["flag", "sync"])
        XCTAssertEqual(RankedChoiceOrder.answer(["flag", "sync", "settings"], topK: nil).count, 3)
    }

    func testReviewCountsOnlyCompleteItems() {
        let items = ["changelog", "rollback"].map { PanelOption(id: $0, label: $0, description: nil) }
        let verdicts = [ReviewVerdict(id: "ok", label: "Confirmed", requiresNote: false),
                        ReviewVerdict(id: "no", label: "Cannot confirm", requiresNote: true)]
        var value = PanelValue.null
        value = ItemReviewAnswer.setting(value, item: "changelog", verdict: "ok", note: nil)
        value = ItemReviewAnswer.setting(value, item: "rollback", verdict: "no", note: nil)
        XCTAssertEqual(ItemReviewAnswer.answeredCount(value, items: items, verdicts: verdicts), 1,
            "A verdict that needs a note is not answered until the note is written")
        value = ItemReviewAnswer.setting(value, item: "rollback", verdict: nil, note: "Old schema only")
        XCTAssertEqual(ItemReviewAnswer.answeredCount(value, items: items, verdicts: verdicts), 2)
        XCTAssertEqual(ItemReviewAnswer.verdict(value, item: "rollback"), "no")
        value = ItemReviewAnswer.setting(value, item: "rollback", verdict: nil, note: "")
        XCTAssertNil(value.object?["rollback"]?.object?["note"], "An emptied note is removed, not sent as \"\"")
    }
}
