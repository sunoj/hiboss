// Layout math for Twitter-style progress media groups.
// Exports: ProgressMediaLayoutTests.
// Dependencies: XCTest, HiBoss app target.

import XCTest
@testable import HiBoss

final class ProgressMediaLayoutTests: XCTestCase {
    func testMissingDimensionsUseSixteenNine() {
        XCTAssertEqual(
            ProgressMediaLayout.clampedAspect(width: nil, height: nil),
            16 / 9,
            accuracy: 0.0001
        )
    }

    func testPortraitIsClampedToThreeFour() {
        XCTAssertEqual(
            ProgressMediaLayout.clampedAspect(width: 100, height: 200),
            3 / 4,
            accuracy: 0.0001
        )
    }

    func testLandscapeIsClampedToTwoOne() {
        XCTAssertEqual(
            ProgressMediaLayout.clampedAspect(width: 300, height: 100),
            2,
            accuracy: 0.0001
        )
    }

    func testUnclampedRatiosPassThrough() {
        XCTAssertEqual(
            ProgressMediaLayout.clampedAspect(width: 16, height: 9),
            16 / 9,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ProgressMediaLayout.clampedAspect(width: 3, height: 4),
            3 / 4,
            accuracy: 0.0001
        )
    }

    func testMeasuredRatioIsUsedWhenDimensionsAreMissing() {
        XCTAssertEqual(
            ProgressMediaLayout.clampedAspect(width: nil, height: nil, measured: 0.5),
            3 / 4,
            accuracy: 0.0001
        )
    }

    func testServerDimensionsWinOverMeasured() {
        XCTAssertEqual(
            ProgressMediaLayout.clampedAspect(width: 16, height: 9, measured: 0.5),
            16 / 9,
            accuracy: 0.0001
        )
    }

    func testDurationLabelFormatsMinutesAndSeconds() {
        XCTAssertEqual(ProgressMediaLayout.durationLabel(milliseconds: 0), "0:00")
        XCTAssertEqual(ProgressMediaLayout.durationLabel(milliseconds: 15_000), "0:15")
        XCTAssertEqual(ProgressMediaLayout.durationLabel(milliseconds: 65_000), "1:05")
    }
}
