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
}
