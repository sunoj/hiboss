// Verifies bulk date grouping preserves the per-item classifier across calendar boundaries.
// Exports: BoxDateGroupingTests with daylight-saving, year, invalid-date and ordering fixtures.
// Dependencies: Foundation, HibossKit and the Box presentation helpers.

import Foundation
import HibossKit
import XCTest
@testable import HibossIsland

final class BoxDateGroupingTests: XCTestCase {
    func testBulkGroupingMatchesIndividualClassificationAcrossCalendarBoundaries() throws {
        let formatter = ISO8601DateFormatter()
        for identifier in [Calendar.Identifier.gregorian, .buddhist] {
            for zone in ["America/Los_Angeles", "Asia/Bangkok"] {
                var calendar = Calendar(identifier: identifier)
                calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
                for raw in ["2026-03-08T12:00:00Z", "2026-11-01T12:00:00Z", "2027-01-01T00:00:00Z"] {
                    let now = try XCTUnwrap(ISODate.parse(raw))
                    let items = (-240...240).map { hour in
                        BoxBrowserFixtures.item("hour-\(hour)", createdAt:
                            formatter.string(from: now.addingTimeInterval(Double(hour) * 3600)))
                    } + [BoxBrowserFixtures.item("invalid", createdAt: "invalid")]
                    let expected = Dictionary(grouping: items) {
                        BoxDateSection.section(for: $0.createdAt, now: now, calendar: calendar)
                    }
                    XCTAssertEqual(BoxDateSection.grouped(items, now: now, calendar: calendar), expected,
                        "\(identifier), \(zone), \(raw)")
                }
            }
        }
    }
}
