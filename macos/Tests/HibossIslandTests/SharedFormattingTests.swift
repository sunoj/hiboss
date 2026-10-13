// Verifies compact timestamps with fixed calendars and canonical answer-source spelling.
// Exports: SharedFormattingTests for elapsed time, Buddhist years, and calendar-day boundaries.
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
        XCTAssertEqual(format("2026-10-13T08:58:00Z", calendar), "2 min ago")
        XCTAssertEqual(format("2026-10-12T08:58:00Z", calendar), "Yesterday 08:58")
        XCTAssertEqual(format("2026-04-03T08:58:00Z", calendar), "3 Apr 08:58")
        XCTAssertEqual(format("2025-04-03T08:58:00Z", calendar), "3 Apr 2025 08:58")
    }

    func testBuddhistCalendarOmitsCurrentYearAndRetainsOlderBuddhistYear() throws {
        let calendar = try calendar(.buddhist)
        XCTAssertEqual(format("2026-10-13T08:58:00Z", calendar), "2 min ago")
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
            locale: Locale(identifier: "zh_Hans_CN")), "7分钟前")
        let older = try XCTUnwrap(ISODate.parse("2026-10-13T04:58:00Z"))
        XCTAssertEqual(SharedTimestamp.string(older, now: localNow, calendar: calendar,
            locale: Locale(identifier: "zh_Hans_CN")), "昨天 11:58")
    }

    func testRelativeBoundariesInChineseAndEnglish() throws {
        let calendar = try calendar(.gregorian)
        let cases: [(TimeInterval, String, String)] = [
            (0, "刚刚", "Just now"), (59, "刚刚", "Just now"),
            (25 * 60, "25分钟前", "25 min ago"),
            (10 * 3600, "10小时前", "10 hr ago"),
            (10 * 3600 + 25 * 60, "10小时25分钟前", "10 hr 25 min ago"),
            (11 * 3600 + 59 * 60, "11小时59分钟前", "11 hr 59 min ago"),
            (12 * 3600, "昨天 21:00", "Yesterday 21:00"),
            (-60, "09:01", "09:01")
        ]
        for (elapsed, chinese, english) in cases {
            let date = now.addingTimeInterval(-elapsed)
            XCTAssertEqual(SharedTimestamp.string(date, now: now, calendar: calendar,
                locale: Locale(identifier: "zh_Hans_CN")), chinese, "elapsed: \(elapsed)")
            XCTAssertEqual(SharedTimestamp.string(date, now: now, calendar: calendar,
                locale: locale), english, "elapsed: \(elapsed)")
        }
    }

    func testBuddhistCalendarUsesElapsedHoursAndMinutesInBothLanguages() throws {
        let calendar = try calendar(.buddhist, zone: "Asia/Bangkok")
        let date = now.addingTimeInterval(-(10 * 3600 + 25 * 60))
        XCTAssertEqual(SharedTimestamp.string(date, now: now, calendar: calendar,
            locale: locale), "10 hr 25 min ago")
        XCTAssertEqual(SharedTimestamp.string(date, now: now, calendar: calendar,
            locale: Locale(identifier: "zh_Hans_CN")), "10小时25分钟前")
    }

    func testElapsedMinutesTruncateAndOlderTodayKeepsClock() throws {
        let calendar = try calendar(.gregorian)
        XCTAssertEqual(SharedTimestamp.string(now.addingTimeInterval(-3599), now: now,
            calendar: calendar, locale: locale), "59 min ago")
        XCTAssertEqual(SharedTimestamp.string(now.addingTimeInterval(-43199), now: now,
            calendar: calendar, locale: locale), "11 hr 59 min ago")
        XCTAssertEqual(SharedTimestamp.string(now, now: now.addingTimeInterval(12 * 3600),
            calendar: calendar, locale: locale), "09:00")
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
