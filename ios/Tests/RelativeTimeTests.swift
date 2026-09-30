// Time-display safety tests for relative labels and Live Activity countdowns.
// Exports: RelativeTimeTests covering locale output and valid timer intervals.
// Dependencies: XCTest, HiBoss app target.

import XCTest
@testable import HiBoss

final class RelativeTimeTests: XCTestCase {
    /// The invariant is "the system formatter decides the wording", not "the wording
    /// avoids some English substring" — `RelativeDateTimeFormatter` itself renders
    /// en_US as "1h ago", so asserting on substrings tests the wrong thing.
    func testRecentTimesUseRelativeFormatterForTheLocale() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let hourAgo = now.addingTimeInterval(-3600)

        for identifier in ["en_US", "zh_CN", "ja_JP", "ko_KR"] {
            let locale = Locale(identifier: identifier)
            XCTAssertEqual(
                RelativeTime.short(from: hourAgo, now: now, locale: locale),
                systemRelativeString(for: hourAgo, relativeTo: now, locale: locale),
                "\(identifier) should come from the system formatter, not hand-built text"
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
        let shipped = ["en_US", "zh_CN", "th_TH", "es_ES", "hi_IN", "ar_SA", "pt_BR", "fr_FR", "ja_JP", "ru_RU"]
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
