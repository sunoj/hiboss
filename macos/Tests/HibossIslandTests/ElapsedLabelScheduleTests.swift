// Verifies that cached read-status ages tick only when their visible text can change.
// Exports: ElapsedLabelScheduleTests for coarse elapsed formatting and schedule cadence.
// Dependencies: XCTest, SwiftUI TimelineSchedule and AttentionClock.

import SwiftUI
import XCTest
@testable import HibossIsland

final class ElapsedLabelScheduleTests: XCTestCase {
    private let en = Locale(identifier: "en_US")

    func testCoarseFormatDropsSecondsAfterTheFirstMinute() {
        XCTAssertEqual(AttentionClock.format(seconds: 42, coarse: true, locale: en), "42s")
        XCTAssertEqual(AttentionClock.format(seconds: 303, coarse: true, locale: en), "5m")
        XCTAssertEqual(AttentionClock.format(seconds: 303, locale: en), "5m 3s")
        XCTAssertEqual(AttentionClock.format(seconds: 3_720, coarse: true, locale: en), "1h 2m")
    }

    func testScheduleTicksEverySecondOnlyInTheFirstMinute() {
        let since = Date(timeIntervalSinceReferenceDate: 1_000)
        let dates = Array(ElapsedLabelSchedule(since: since)
            .entries(from: since.addingTimeInterval(58.5), mode: .normal).prefix(5))
        XCTAssertEqual(dates.map { $0.timeIntervalSince(since) }, [58.5, 59, 60, 120, 180])
    }

    func testScheduleTextChangesAtEveryEntryAndNeverBetween() {
        let since = Date(timeIntervalSinceReferenceDate: 1_000)
        let dates = Array(ElapsedLabelSchedule(since: since)
            .entries(from: since.addingTimeInterval(3_000), mode: .normal).prefix(20))
        for (date, next) in zip(dates, dates.dropFirst()) {
            let label = AttentionClock.elapsed(since: since, now: date, coarse: true, locale: en)
            XCTAssertEqual(label, AttentionClock.elapsed(since: since, now: next.addingTimeInterval(-0.01),
                coarse: true, locale: en), "Text changed between ticks at \(date)")
            XCTAssertNotEqual(label, AttentionClock.elapsed(since: since, now: next, coarse: true, locale: en))
        }
        XCTAssertEqual(dates[1].timeIntervalSince(dates[0]), 60)
    }
}
