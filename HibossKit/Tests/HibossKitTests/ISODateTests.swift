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
}
