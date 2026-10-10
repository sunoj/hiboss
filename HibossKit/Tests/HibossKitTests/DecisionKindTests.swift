// Covers the shared decision predicate both apps use; it must match the server query.

import XCTest
@testable import HibossKit

final class DecisionKindTests: XCTestCase {
    func testMatchesServerShape() {
        XCTAssertTrue(TodayTestSupport.message("o", options: ["Yes"]).isDecision)
        XCTAssertTrue(TodayTestSupport.message("b", mode: "blocking").isDecision)
        XCTAssertFalse(TodayTestSupport.message("n").isDecision)
        XCTAssertFalse(TodayTestSupport.message("d", defaultOption: "Yes").isDecision)
        XCTAssertFalse(TodayTestSupport.message("out", options: ["Yes"], direction: "boss_to_agent").isDecision)
        XCTAssertFalse(TodayTestSupport.message("peer", mode: "blocking", direction: "agent_to_agent").isDecision)
    }
}
