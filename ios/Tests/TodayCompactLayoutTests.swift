// Verifies Today's narrow and short layout decisions: meta-line fallbacks and header compaction.
// Exports TodayCompactLayoutTests for DecisionMetaLine and TodayHeaderLayout.
// Dependencies: XCTest and HiBoss.

import XCTest
@testable import HiBoss

final class TodayCompactLayoutTests: XCTestCase {
    func testMetaLineDropsBranchBeforeAgent() {
        let line = DecisionMetaLine(project: "prod-release", branch: "release/v2.4", agent: "worker")
        XCTAssertEqual(line.lines, ["prod-release · release/v2.4 · worker", "prod-release · worker"])
        XCTAssertEqual(line.tails.last, "worker")
    }

    func testMetaLineDoesNotRepeatABranchThatNamesTheProject() {
        let line = DecisionMetaLine(project: "main", branch: " main ", agent: "worker")
        XCTAssertEqual(line.lines, ["main · worker"])
    }

    func testMetaLineIgnoresBlankParts() {
        XCTAssertEqual(DecisionMetaLine(project: "p", branch: "  ", agent: nil).lines, ["p"])
        XCTAssertEqual(DecisionMetaLine(project: "p", branch: "b", agent: "").lines, ["p · b"])
    }

    func testHeaderCompactsOnlyOnShortContainers() {
        XCTAssertTrue(TodayHeaderLayout.isCompact(containerHeight: 678))  // folded outer display
        XCTAssertTrue(TodayHeaderLayout.isCompact(containerHeight: 667))  // 4.7-inch phones
        XCTAssertTrue(TodayHeaderLayout.isCompact(containerHeight: 700))
        XCTAssertFalse(TodayHeaderLayout.isCompact(containerHeight: 701))
        XCTAssertFalse(TodayHeaderLayout.isCompact(containerHeight: 874))  // iPhone 17
        XCTAssertFalse(TodayHeaderLayout.isCompact(containerHeight: 0))  // not yet measured
    }
}
