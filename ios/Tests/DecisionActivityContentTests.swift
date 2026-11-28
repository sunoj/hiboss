// Verifies that in-flight Live Activity presentation is optional persisted state.
// Exports DecisionActivityContentTests; existing activities can omit progress markers.
// Dependencies: XCTest, Foundation and the shared ActivityKit content contract.

import Foundation
import XCTest
@testable import HiBoss

final class DecisionActivityContentTests: XCTestCase {
    func testActivityWithoutProgressMarkersRemainsReadable() throws {
        let payload = Data(#"{"body":"Choose","options":["Yes"],"priority":"high"}"#.utf8)
        let state = try JSONDecoder().decode(DecisionActivityAttributes.ContentState.self, from: payload)
        XCTAssertNil(state.submissionProgressVisible)
        XCTAssertNil(state.submissionIsSlow)
        XCTAssertNil(state.replyFailed)
        XCTAssertEqual(state.options, ["Yes"])
    }

    func testRingUsesOriginalIntervalAndRejectsMissingOrInvertedBounds() {
        let asked = Date(timeIntervalSince1970: 100)
        let now = asked.addingTimeInterval(20)
        let deadline = asked.addingTimeInterval(60)

        XCTAssertEqual(DecisionTimerRange.progress(from: asked, until: deadline, now: now), asked...deadline)
        XCTAssertNil(DecisionTimerRange.progress(from: nil, until: deadline, now: now))
        XCTAssertNil(DecisionTimerRange.progress(from: asked, until: nil, now: now))
        XCTAssertNil(DecisionTimerRange.progress(from: asked, until: asked, now: now))
        XCTAssertNil(DecisionTimerRange.progress(from: now, until: asked, now: now))
    }
}
