// Session board status catalog: known words get a glyph + localized label.
// Exports: SessionStatusStyleTests covering the five live statuses and fallbacks.
// Dependencies: XCTest, HiBoss app target.

import XCTest
@testable import HiBoss

final class SessionStatusStyleTests: XCTestCase {
    func testKnownStatusesUseLocalizedLabelsAndDistinctIcons() {
        let working = SessionStatusStyle(word: "working")
        let blocked = SessionStatusStyle(word: "blocked")
        let waiting = SessionStatusStyle(word: "waiting")
        let idle = SessionStatusStyle(word: "idle")
        let completed = SessionStatusStyle(word: "completed")

        XCTAssertEqual(working?.label, String(localized: "Working"))
        XCTAssertEqual(blocked?.label, String(localized: "Blocked"))
        XCTAssertEqual(waiting?.label, String(localized: "Waiting"))
        XCTAssertEqual(idle?.label, String(localized: "Idle"))
        XCTAssertEqual(completed?.label, String(localized: "Completed"))

        let icons = [working, blocked, waiting, idle, completed].compactMap { $0?.icon }
        XCTAssertEqual(Set(icons).count, 5)
        XCTAssertEqual(working?.icon, "ellipsis.circle.fill")
        XCTAssertEqual(blocked?.icon, "exclamationmark.octagon.fill")
        XCTAssertEqual(waiting?.icon, "clock.fill")
        XCTAssertEqual(idle?.icon, "pause.circle.fill")
        XCTAssertEqual(completed?.icon, "checkmark.circle.fill")
    }

    func testEmptyWordHasNoStyleAndUnknownWordsStayReadable() {
        XCTAssertNil(SessionStatusStyle(word: ""))
        XCTAssertEqual(SessionStatusStyle(word: "paused")?.label, "Paused")
        XCTAssertEqual(SessionStatusStyle(word: "paused")?.icon, "circle.fill")
    }
}
