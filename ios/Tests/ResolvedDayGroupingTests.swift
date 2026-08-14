// Day grouping for the handled-decisions screen: newest day first.
// Exports: ResolvedDayGroupingTests covering order and the empty input.
// Dependencies: XCTest, HiBoss app target, HibossKit.

import HibossKit
import XCTest
@testable import HiBoss

final class ResolvedDayGroupingTests: XCTestCase {
    func testGroupsNewestDayFirstAndNewestWithinDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let older = message("a", at: "2026-08-12T10:00:00Z")
        let morning = message("b", at: "2026-08-14T09:00:00Z")
        let evening = message("c", at: "2026-08-14T18:00:00Z")
        let groups = ResolvedDayGrouping.groups(
            from: [older, morning, evening],
            calendar: calendar
        )
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].messages.map(\.id), ["c", "b"])
        XCTAssertEqual(groups[1].messages.map(\.id), ["a"])
        let day14 = calendar.startOfDay(for: date("2026-08-14T00:00:00Z"))
        let day12 = calendar.startOfDay(for: date("2026-08-12T00:00:00Z"))
        XCTAssertEqual(groups[0].day, day14)
        XCTAssertEqual(groups[1].day, day12)
    }

    func testEmptyInputYieldsNoGroups() {
        XCTAssertTrue(ResolvedDayGrouping.groups(from: []).isEmpty)
    }

    private func message(_ id: String, at createdAt: String) -> HistoryMessage {
        HistoryMessage(
            id: MessageID(rawValue: id),
            body: id,
            direction: "agent_to_boss",
            status: "replied",
            priority: "normal",
            metadata: MessageMetadata(options: ["Yes", "No"]),
            createdAt: createdAt
        )
    }

    private func date(_ raw: String) -> Date {
        ISOTimestamp.date(from: raw) ?? .distantPast
    }
}
