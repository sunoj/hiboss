// Session status mapping: known words get a glyph + localized label, and Home agrees with Sessions.
// Exports: SessionStatusStyleTests covering the five live statuses, parsing, fallbacks, and Home.
// Dependencies: XCTest, SwiftUI Color, HiBoss app target.

import SwiftUI
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
        XCTAssertEqual(waiting?.label, String(localized: "Waiting on you"))
        XCTAssertEqual(idle?.label, String(localized: "Idle"))
        XCTAssertEqual(completed?.label, String(localized: "Completed"))

        let icons = [working, blocked, waiting, idle, completed].compactMap { $0?.icon }
        XCTAssertEqual(Set(icons).count, 5)
        XCTAssertEqual(working?.icon, "ellipsis.circle.fill")
        XCTAssertEqual(blocked?.icon, "exclamationmark.octagon.fill")
        XCTAssertEqual(waiting?.icon, "hand.raised.fill")
        XCTAssertEqual(idle?.icon, "pause.circle.fill")
        XCTAssertEqual(completed?.icon, "checkmark.circle.fill")
    }

    func testEmptyWordHasNoStyleAndUnknownWordsStayReadable() {
        XCTAssertNil(SessionStatusStyle(word: ""))
        XCTAssertEqual(SessionStatusStyle(word: "paused")?.label, "Paused")
        XCTAssertEqual(SessionStatusStyle(word: "paused")?.icon, "circle.fill")
    }

    func testParsingTrimsAndIgnoresCase() {
        XCTAssertEqual(SessionStatus(word: " Waiting\n"), .waiting)
        XCTAssertEqual(SessionStatus(word: "BLOCKED"), .blocked)
        XCTAssertNil(SessionStatus(word: nil))
        XCTAssertNil(SessionStatus(word: "paused"))
        XCTAssertEqual(SessionStatusStyle(word: " waiting ")?.label, String(localized: "Waiting on you"))
    }

    func testOnlyBlockedIsRedAndWaitingIsOrange() {
        XCTAssertEqual(SessionStatus.blocked.tint, Theme.negative)
        XCTAssertEqual(SessionStatus.waiting.tint, Theme.warn)
        for status in [SessionStatus.working, .idle, .completed] {
            XCTAssertEqual(status.tint, Theme.ink2, "\(status)")
        }
    }

    /// Home's group header and the Sessions card read the same words, glyph and tint.
    func testHomeWaitingGroupUsesTheSessionsWording() {
        let card = SessionStatusStyle(word: "waiting")
        XCTAssertEqual(String(localized: AttentionGroup.waitingOnYou.title), card?.label)
        XCTAssertEqual(AttentionGroup.waitingOnYou.symbol, card?.icon)
        XCTAssertEqual(AttentionGroup.waitingOnYou.tint, card?.tint)
        XCTAssertEqual(AttentionGroup.autoDecision.tint, Theme.ink2)
        XCTAssertEqual(AttentionGroup.priority.tint, Theme.ink2)
    }
}
