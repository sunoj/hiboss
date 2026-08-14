// RelativeTime locale-driven formatting tests.
// Exports: RelativeTimeTests covering system relative strings vs hand-built English.
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
}
