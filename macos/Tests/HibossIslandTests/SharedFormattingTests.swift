// Verifies compact timestamps with fixed calendars and canonical answer-source spelling.
// Exports: SharedFormattingTests, including Buddhist years, local midnight, and Chinese yesterday.
// Dependencies: Foundation, XCTest, and production formatting helpers.

import Foundation
import HibossKit
import XCTest
@testable import HibossIsland

final class SharedFormattingTests: XCTestCase {
    private let now = ISODate.parse("2026-10-13T09:00:00Z")!
    private let locale = Locale(identifier: "en_GB")

    func testTodayYesterdayAndEarlierThisYearOmitTheYear() throws {
        let calendar = try calendar(.gregorian)
        XCTAssertEqual(format("2026-10-13T08:58:00Z", calendar), "08:58")
        XCTAssertEqual(format("2026-10-12T08:58:00Z", calendar), "Yesterday 08:58")
        XCTAssertEqual(format("2026-04-03T08:58:00Z", calendar), "3 Apr 08:58")
        XCTAssertEqual(format("2025-04-03T08:58:00Z", calendar), "3 Apr 2025 08:58")
    }

    func testBuddhistCalendarOmitsCurrentYearAndRetainsOlderBuddhistYear() throws {
        let calendar = try calendar(.buddhist)
        XCTAssertEqual(format("2026-10-13T08:58:00Z", calendar), "08:58")
        XCTAssertEqual(format("2026-10-12T08:58:00Z", calendar), "Yesterday 08:58")
        XCTAssertEqual(format("2026-04-03T08:58:00Z", calendar), "3 Apr 08:58")
        let older = format("2025-04-03T08:58:00Z", calendar)
        XCTAssertTrue(older.contains("2568"), older)
        XCTAssertFalse(older.contains("2025"), older)
    }

    func testYesterdayUsesChineseCatalogAndCalendarDayAcrossLocalMidnight() throws {
        let calendar = try calendar(.gregorian, zone: "Asia/Bangkok")
        let localNow = try XCTUnwrap(ISODate.parse("2026-10-13T17:05:00Z"))
        let date = try XCTUnwrap(ISODate.parse("2026-10-13T16:58:00Z"))
        XCTAssertEqual(SharedTimestamp.string(date, now: localNow, calendar: calendar,
            locale: Locale(identifier: "zh_Hans_CN")), "昨天 23:58")
    }

    func testYesterdayAcrossNewYearStillUsesYesterday() throws {
        let calendar = try calendar(.buddhist)
        let newYear = try XCTUnwrap(ISODate.parse("2027-01-01T09:00:00Z"))
        let date = try XCTUnwrap(ISODate.parse("2026-12-31T08:58:00Z"))
        XCTAssertEqual(SharedTimestamp.string(date, now: newYear, calendar: calendar,
            locale: locale), "Yesterday 08:58")
    }

    func testBoxAddedUsesSharedCalendarFormattingAndPreservesInvalidInput() throws {
        let calendar = try calendar(.buddhist)
        for raw in ["2026-10-13T08:58:00Z", "2026-10-12T08:58:00Z", "2025-04-03T08:58:00Z"] {
            XCTAssertEqual(BoxTime.absolute(raw, now: now, locale: locale, calendar: calendar),
                format(raw, calendar))
        }
        XCTAssertEqual(BoxTime.absolute("invalid", now: now), "invalid")
    }

    func testKnownAnswerSourcesUsePlatformSpellingAndUnknownNamesCapitalize() {
        let sources = ["ios": "iOS", "ipados": "iPadOS", "macos": "macOS", "watchos": "watchOS",
            "cli": "CLI", "web": "Web", "telegram": "Telegram", "discord": "Discord"]
        for (source, expected) in sources {
            XCTAssertEqual(AnswerSource.label(source), expected)
            XCTAssertEqual(AnswerSource.label(source.uppercased()), expected)
        }
        XCTAssertEqual(AnswerSource.label("custom client"), "Custom Client")
    }

    func testMacOSAndEmptyAnswerSourcesRemainHidden() {
        XCTAssertNil(AnswerSource.visibleLabel("macos"))
        XCTAssertNil(AnswerSource.visibleLabel("macOS"))
        XCTAssertNil(AnswerSource.visibleLabel(""))
        XCTAssertEqual(AnswerSource.visibleLabel("ios"), "iOS")
    }

    private func calendar(_ identifier: Calendar.Identifier, zone: String = "UTC") throws -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        return calendar
    }

    private func format(_ raw: String, _ calendar: Calendar) -> String {
        SharedTimestamp.string(ISODate.parse(raw)!, now: now, calendar: calendar, locale: locale)
    }
}
