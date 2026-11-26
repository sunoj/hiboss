// Verifies that a paused timeline schedule stops ticking and a running one keeps its base cadence.
// Exports SurfaceVisibilityTests; dependencies: XCTest, SwiftUI and PausableTimelineSchedule.

import SwiftUI
import XCTest
@testable import HibossKit

final class SurfaceVisibilityTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 500)

    func testPausedScheduleYieldsOnlyItsStart() {
        let entries = Array(PeriodicTimelineSchedule(from: start, by: 1).paused(true)
            .entries(from: start.addingTimeInterval(2.5), mode: .normal).prefix(5))
        XCTAssertEqual(entries, [start.addingTimeInterval(2.5)])
    }

    func testRunningScheduleMatchesItsBase() {
        let base = PeriodicTimelineSchedule(from: start, by: 1)
        let from = start.addingTimeInterval(2.5)
        XCTAssertEqual(Array(base.paused(false).entries(from: from, mode: .normal).prefix(4)),
            Array(base.entries(from: from, mode: .normal).prefix(4)))
    }

    func testSurfacesAreVisibleUnlessAHostSaysOtherwise() {
        XCTAssertTrue(EnvironmentValues().surfaceIsVisible)
    }
}
