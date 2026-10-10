// Tests for memoized ISO 8601 parsing used on every render.
// Exports: ISODateTests.
// Dependencies: XCTest, HibossKit.

import HibossKit
import XCTest

final class ISODateTests: XCTestCase {
    func testParsesWholeAndFractionalSecondsTheSame() {
        let whole = ISODate.parse("2026-09-30T08:00:00Z")
        let fractional = ISODate.parse("2026-09-30T08:00:00.000Z")
        XCTAssertEqual(whole, Date(timeIntervalSince1970: 1_790_755_200))
        XCTAssertEqual(fractional, whole)
    }

    func testInvalidAndMissingValuesStayNilWhenRepeated() {
        XCTAssertNil(ISODate.parse(nil))
        XCTAssertNil(ISODate.parse(""))
        XCTAssertNil(ISODate.parse("not a date"))
        XCTAssertNil(ISODate.parse("not a date"), "a cached failure must still read as nil")
    }

    func testParsesSQLiteTimestampsAsUTC() {
        XCTAssertEqual(ISODate.parse("2026-09-30 08:00:00"), ISODate.parse("2026-09-30T08:00:00Z"))
        XCTAssertEqual(ISODate.parse("2026-09-30 08:00:00"), Date(timeIntervalSince1970: 1_790_755_200))
    }

    /// The server stores SQLite timestamps, and a snapshot sorts every history message by
    /// date on each refresh. Building a formatter per comparison took seconds for this list.
    func testSnapshotOfSQLiteDatedHistoryStaysFast() {
        let base = TodayTestSupport.now.timeIntervalSince1970
        let history = (0..<4_000).map { index in
            let date = Date(timeIntervalSince1970: base - Double(index * 7 % 3_600))
            let sql = date.ISO8601Format().replacingOccurrences(of: "T", with: " ")
                .replacingOccurrences(of: "Z", with: "")
            return TodayTestSupport.message("m\(index)", createdAt: sql)
        }
        let started = Date()
        _ = TodayTestSupport.snapshot(history)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0)
    }

    func testOffsetsAndMalformedShapesStillParseOrFail() {
        XCTAssertEqual(ISODate.parse("2026-09-30T15:00:00+07:00"), ISODate.parse("2026-09-30T08:00:00Z"))
        XCTAssertEqual(ISODate.parse("2026-09-30T15:00:00.250+07:00")?.timeIntervalSince1970,
                       1_790_755_200.25)
        XCTAssertNil(ISODate.parse("2026-09-30 08:00"))
        XCTAssertNil(ISODate.parse("2026-09-30"))
    }
}
