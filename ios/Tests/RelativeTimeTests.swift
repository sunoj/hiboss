// Time-display safety tests for relative labels and Live Activity countdowns.
// Exports: RelativeTimeTests covering locale output and valid timer intervals.
// Dependencies: XCTest, HiBoss app target.

import XCTest
@testable import HiBoss

final class RelativeTimeTests: XCTestCase {
    func testRecordedTimeBoundariesUseCompactChineseAndEnglish() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cases: [(Double, String, String)] = [
            (0, "刚刚", "Just now"), (59, "刚刚", "Just now"),
            (60, "1分钟前", "1 min ago"), (1500, "25分钟前", "25 min ago"),
            (3600, "1小时前", "1 hr ago"), (37500, "10小时25分钟前", "10 hr 25 min ago"),
            (36000, "10小时前", "10 hr ago")
        ]
        for (seconds, chinese, english) in cases {
            let date = now.addingTimeInterval(-seconds)
            XCTAssertEqual(RelativeTime.short(from: date, now: now, locale: Locale(identifier: "zh-Hans")),
                           chinese)
            XCTAssertEqual(RelativeTime.short(from: date, now: now, locale: Locale(identifier: "en")),
                           english)
        }
    }

    func testFutureRecordedTimesUseAbsoluteDates() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let label = RelativeTime.short(from: now.addingTimeInterval(60), now: now,
                                       locale: Locale(identifier: "en"))
        XCTAssertFalse(label.contains("in "))
        XCTAssertTrue(label.contains(":"))
    }

    func testTwelveHourBoundaryAndAbsoluteCalendarRules() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(ISOTimestamp.date(from: "2026-10-13T22:00:00Z"))
        let locale = Locale(identifier: "zh-Hans")
        let cases = [("2026-10-13T10:00:01Z", "11小时59分钟前"),
                     ("2026-10-13T10:00:00Z", "10:00"),
                     ("2026-10-12T22:30:00Z", "昨天 22:30"),
                     ("2026-10-13T22:01:00Z", "22:01")]
        for (raw, expected) in cases {
            let date = try XCTUnwrap(ISOTimestamp.date(from: raw))
            XCTAssertEqual(RelativeTime.short(from: date, now: now, locale: locale, calendar: calendar),
                           expected)
        }
        let earlier = try XCTUnwrap(ISOTimestamp.date(from: "2026-02-04T14:15:00Z"))
        let old = try XCTUnwrap(ISOTimestamp.date(from: "2025-02-04T14:15:00Z"))
        let recentLabel = RelativeTime.short(from: earlier, now: now, locale: locale, calendar: calendar)
        XCTAssertFalse(recentLabel.contains("2026"))
        XCTAssertTrue(recentLabel.contains("2月4日"))
        XCTAssertTrue(recentLabel.contains("14:15"))
        XCTAssertTrue(RelativeTime.short(from: old, now: now, locale: locale, calendar: calendar)
            .contains("2025"))
    }

    func testBuddhistCalendarOmitsItsCurrentYearForRecordsAndDeadlines() throws {
        var calendar = Calendar(identifier: .buddhist)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(ISOTimestamp.date(from: "2026-10-13T22:00:00Z"))
        for identifier in ["en", "zh-Hans", "th_TH"] {
            let locale = Locale(identifier: identifier)
            for raw in ["2026-02-04T14:15:00Z", "2026-10-14T14:15:00Z"] {
                let date = try XCTUnwrap(ISOTimestamp.date(from: raw))
                let label = RelativeTime.short(from: date, now: now, locale: locale, calendar: calendar)
                XCTAssertFalse(label.contains("2569"), "\(identifier): \(label)")
                XCTAssertFalse(label.contains("BE"), "\(identifier): \(label)")
                XCTAssertTrue(label.contains(":"), "Absolute dates include the time")
                XCTAssertEqual(label, RelativeTime.absolute(from: date, now: now,
                                                            locale: locale, calendar: calendar))
                let heading = RelativeTime.absolute(from: date, now: now, locale: locale,
                                                    calendar: calendar, includesTime: false)
                XCTAssertFalse(heading.contains("2569"))
            }
            let old = try XCTUnwrap(ISOTimestamp.date(from: "2025-02-04T14:15:00Z"))
            XCTAssertTrue(RelativeTime.short(from: old, now: now, locale: locale, calendar: calendar)
                .contains("2568"))
        }
    }

    func testAbsoluteEnglishYesterdayAndUserTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Bangkok"))
        let now = try XCTUnwrap(ISOTimestamp.date(from: "2026-10-13T15:00:00Z"))
        let yesterday = try XCTUnwrap(ISOTimestamp.date(from: "2026-10-12T15:30:00Z"))
        let label = RelativeTime.short(from: yesterday, now: now,
                                       locale: Locale(identifier: "en_US"), calendar: calendar)
        XCTAssertEqual(label, "Yesterday 10:30\u{202F}PM")
    }

    func testOtherLocalesKeepLocalizedNowAndYesterday() throws {
        var calendar = Calendar(identifier: .buddhist)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(ISOTimestamp.date(from: "2026-10-13T22:00:00Z"))
        let yesterday = now.addingTimeInterval(-86400)
        for identifier in ["th_TH", "ja_JP", "fr_FR"] {
            let locale = Locale(identifier: identifier)
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = locale
            formatter.dateTimeStyle = .named
            XCTAssertEqual(RelativeTime.short(from: now, now: now, locale: locale, calendar: calendar),
                           formatter.localizedString(from: DateComponents(second: 0)))
            XCTAssertTrue(RelativeTime.short(from: yesterday, now: now, locale: locale, calendar: calendar)
                .hasPrefix(formatter.localizedString(from: DateComponents(day: -1))))
        }
    }

    /// English and Chinese use the compact product wording; other locales use CLDR.
    func testRecentTimesUseRelativeFormatterForTheLocale() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let hourAgo = now.addingTimeInterval(-3600)

        for identifier in ["en_US", "zh_CN", "ja_JP", "ko_KR"] {
            let locale = Locale(identifier: identifier)
            XCTAssertEqual(
                RelativeTime.short(from: hourAgo, now: now, locale: locale),
                identifier == "en_US" ? "1 hr ago" : identifier == "zh_CN" ? "1小时前"
                    : systemRelativeString(for: hourAgo, relativeTo: now, locale: locale),
                "\(identifier) must use its localized wording"
            )
        }

        // Distinct per locale, so nothing is pinned to English.
        let rendered = ["en_US", "zh_CN", "ja_JP", "ko_KR"].map {
            RelativeTime.short(from: hourAgo, now: now, locale: Locale(identifier: $0))
        }
        XCTAssertEqual(Set(rendered).count, rendered.count)
        XCTAssertFalse(rendered.contains(where: \.isEmpty))
    }

    /// Russian's narrowest CLDR past form is a signed number ("-1 мин"); a past time
    /// must read as "ago" in every shipped language.
    func testPastTimesNeverRenderAsNegativeNumbers() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let shipped = ["en_US", "zh_CN", "th_TH", "es_ES", "hi_IN", "ar_SA", "pt_BR", "fr_FR", "ja_JP", "ko_KR", "ru_RU"]
        for identifier in shipped {
            for seconds in [60.0, 3600, 86_400] {
                let text = RelativeTime.short(from: now.addingTimeInterval(-seconds), now: now,
                                              locale: Locale(identifier: identifier))
                XCTAssertFalse(text.hasPrefix("-") || text.hasPrefix("\u{2212}"), "\(identifier): \(text)")
            }
        }
    }

    private func systemRelativeString(for date: Date, relativeTo now: Date, locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = locale
        return formatter.localizedString(for: date, relativeTo: now)
    }

    func testOlderTimesFallBackToAShortDate() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let twoWeeksAgo = now.addingTimeInterval(-14 * 86_400)
        let formatted = RelativeTime.short(
            from: twoWeeksAgo,
            now: now,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertFalse(formatted.contains("ago"))
        XCTAssertFalse(formatted.isEmpty)
    }

    func testDecisionTimerRejectsAnExpiredDeadline() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertNil(DecisionTimerRange.active(until: now.addingTimeInterval(-1), now: now))
        XCTAssertNil(DecisionTimerRange.active(until: now, now: now))
    }

    func testDecisionTimerBuildsAForwardOnlyInterval() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let deadline = now.addingTimeInterval(60)

        let range = DecisionTimerRange.active(until: deadline, now: now)

        XCTAssertEqual(range?.lowerBound, now)
        XCTAssertEqual(range?.upperBound, deadline)
    }
}
