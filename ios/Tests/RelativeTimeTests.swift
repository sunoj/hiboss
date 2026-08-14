// RelativeTime locale-driven formatting tests.
// Exports: RelativeTimeTests covering system relative strings vs hand-built English.
// Dependencies: XCTest, HiBoss app target.

import XCTest
@testable import HiBoss

final class RelativeTimeTests: XCTestCase {
    func testRecentTimesUseRelativeFormatterForTheLocale() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let hourAgo = now.addingTimeInterval(-3600)
        let en = RelativeTime.short(from: hourAgo, now: now, locale: Locale(identifier: "en_US"))
        let zh = RelativeTime.short(from: hourAgo, now: now, locale: Locale(identifier: "zh_CN"))

        XCTAssertFalse(en.contains("m ago"))
        XCTAssertFalse(en.contains("h ago"))
        XCTAssertNotEqual(en, zh)
        XCTAssertFalse(zh.isEmpty)
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
