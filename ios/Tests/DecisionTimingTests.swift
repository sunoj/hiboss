// Deadline/default projection checks shared by Home cards and message detail.
// Exports: DecisionTimingTests covering original agent text and live expiration boundaries.
// Dependencies: XCTest, HibossKit, HiBoss DecisionTiming.

import HibossKit
import XCTest
@testable import HiBoss

final class DecisionTimingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testLiveDefaultPreservesAgentTextWhileMatchingTrimmedOptions() {
        let timing = DecisionTiming(message: message(deadline: now.addingTimeInterval(60)), now: now)
        XCTAssertEqual(timing.autoDefault, "  Keep original text  ")
        XCTAssertTrue(timing.isAutoDefault("Keep original text"))
        XCTAssertFalse(timing.isAutoDefault("Other choice"))
        XCTAssertEqual(timing.expiresAt, now.addingTimeInterval(60))
    }

    func testDefaultWithoutDeadlineNeverBecomesAutomatic() {
        let timing = DecisionTiming(message: message(deadline: nil), now: now)
        XCTAssertNil(timing.expiresAt)
        XCTAssertNil(timing.autoDefault)
        XCTAssertFalse(timing.isAutoDefault("Keep original text"))
    }

    func testDefaultStopsBeingAutomaticAtDeadline() {
        let source = message(deadline: now.addingTimeInterval(60))
        XCTAssertTrue(DecisionTiming(message: source, now: now).isAutoDefault("Keep original text"))
        let expired = DecisionTiming(message: source, now: now.addingTimeInterval(60))
        XCTAssertNil(expired.autoDefault)
        XCTAssertNil(expired.expiresAt)
        XCTAssertFalse(expired.isAutoDefault("Keep original text"))
    }

    func testWhitespaceDefaultDoesNotHideLiveReplyDeadline() {
        let source = message(deadline: now.addingTimeInterval(60), defaultOption: "  ")
        let timing = DecisionTiming(message: source, now: now)
        XCTAssertEqual(timing.expiresAt, now.addingTimeInterval(60))
        XCTAssertNil(timing.autoDefault)
    }

    private func message(deadline: Date?, defaultOption: String = "  Keep original text  ") -> HistoryMessage {
        HistoryMessage(
            id: "decision-clock", body: "An agent question", direction: "agent_to_boss",
            status: "delivered", priority: "normal",
            metadata: MessageMetadata(options: ["Keep original text", "Other choice"], defaultOption: defaultOption),
            expiresAt: deadline?.ISO8601Format(), createdAt: now.addingTimeInterval(-120).ISO8601Format()
        )
    }
}
