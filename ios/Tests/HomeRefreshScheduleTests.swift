// Tests for Home's re-rank schedule: deadlines first, a minute otherwise.
// Exports: HomeRefreshScheduleTests.
// Dependencies: XCTest, SwiftUI, HiBoss app target.

import SwiftUI
import XCTest
@testable import HiBoss

final class HomeRefreshScheduleTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testFiresJustAfterAnUpcomingDeadlineThenFallsBackToAMinute() {
        let schedule = HomeRefreshSchedule(deadlines: [start.addingTimeInterval(10)])
        let dates = Array(schedule.entries(from: start, mode: .normal).prefix(3))
        XCTAssertEqual(dates, [start, start.addingTimeInterval(10.5), start.addingTimeInterval(70.5)])
    }

    func testPastDeadlinesAreIgnored() {
        let schedule = HomeRefreshSchedule(deadlines: [start.addingTimeInterval(-5)])
        let dates = Array(schedule.entries(from: start, mode: .normal).prefix(2))
        XCTAssertEqual(dates, [start, start.addingTimeInterval(60)])
    }
}
