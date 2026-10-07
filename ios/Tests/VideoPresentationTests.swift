// Protects cached video frames and terminal failure across native player callbacks.
// Exports VideoPresentationTests for buffering and explicit retry transitions.
// Dependencies: XCTest and the looping player's presentation state.

import XCTest
@testable import HiBoss

final class VideoPresentationTests: XCTestCase {
    func testBufferingKeepsTheDisplayedFrame() {
        var state = VideoPresentation()
        state.receive(.ready)
        state.receive(.loading)
        XCTAssertTrue(state.hasFrame)
        XCTAssertEqual(state.phase, .loading)
    }

    func testFailureWaitsForExplicitRetryDespiteReadyCallbacks() {
        var state = VideoPresentation()
        state.receive(.ready)
        state.receive(.failed)
        state.receive(.ready)
        XCTAssertEqual(state.phase, .failed)
        state.reset()
        XCTAssertFalse(state.hasFrame)
        XCTAssertEqual(state.phase, .loading)
        state.receive(.ready)
        XCTAssertEqual(state.phase, .ready)
    }
}
