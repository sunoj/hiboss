// Unit tests for island/window agreement, live merge, clock, and auto-decided history.
// Covers: IslandAttention front item, fallback, and History auto-decided labels.
// Dependencies: XCTest, HibossKit fixtures, AttentionTestSupport.

import HibossKit
import XCTest
@testable import HibossIsland

final class AttentionIslandAgreementTests: XCTestCase {
    private let now = AttentionTestSupport.now
    private func iso(_ date: Date) -> String { AttentionTestSupport.iso(date) }
    private func ask(
        id: MessageID,
        priority: String = "normal",
        options: [String],
        defaultOption: String? = nil,
        isExpired: Bool = false,
        expiresAt: String? = nil,
        createdAt: String? = nil,
        status: String = "delivered",
        sessionLabel: String? = "proj/main",
        sessionStatus: String? = nil
    ) -> HistoryMessage {
        AttentionTestSupport.ask(
            id: id,
            priority: priority,
            options: options,
            defaultOption: defaultOption,
            isExpired: isExpired,
            expiresAt: expiresAt,
            createdAt: createdAt,
            status: status,
            sessionLabel: sessionLabel,
            sessionStatus: sessionStatus,
            now: now
        )
    }

    func testIslandFrontMatchesWindowFront() {
        let blocked = ask(
            id: "blocked",
            options: ["Approve"],
            createdAt: iso(now.addingTimeInterval(-200)),
            sessionStatus: "waiting"
        )
        let live = OptionMessage(
            id: "live-high",
            body: "Live question",
            agentName: "Live Agent",
            metadata: MessageMetadata(options: ["Yes", "No"]),
            sessionLabel: "live/main"
        )
        let liveHistory = ask(
            id: "live-high",
            priority: "high",
            options: ["Yes", "No"],
            createdAt: iso(now.addingTimeInterval(-5)),
            sessionLabel: "live/main",
            sessionStatus: "working"
        )

        let history = [blocked, liveHistory]
        let front = AttentionRanking.frontID(history: history, live: live, now: now)
        let island = IslandAttention.presentation(live: live, history: history, now: now)

        XCTAssertEqual(front, "blocked")
        XCTAssertEqual(island?.message.id, front)
    }

    func testLiveOnlyAutoDecisionMergesWhenMissingFromHistory() {
        let live = OptionMessage(
            id: "live-auto",
            body: "Pick soon",
            agentName: "Agent",
            metadata: MessageMetadata(options: ["A", "B"], defaultOption: "B"),
            expiresAt: iso(now.addingTimeInterval(45)),
            sessionLabel: "proj/main"
        )

        let ranked = AttentionRanking.items(history: [], live: live, now: now)
        let island = IslandAttention.presentation(live: live, history: [], now: now)

        XCTAssertEqual(ranked.map(\.id.rawValue), ["live-auto"])
        XCTAssertEqual(island?.message.id.rawValue, "live-auto")
    }

    func testIslandFallsBackToLiveWhenNothingIsAttention() {
        let live = OptionMessage.fixture(id: "plain", options: ["Continue"])
        let island = IslandAttention.presentation(live: live, history: [], now: now)

        XCTAssertEqual(island?.message.id.rawValue, "plain")
        XCTAssertNil(island?.item)
        XCTAssertTrue(AttentionRanking.items(history: [], live: live, now: now).isEmpty)
    }

    func testClockFormatsRemainingAndElapsed() {
        XCTAssertEqual(AttentionClock.format(seconds: 0), "0s")
        XCTAssertEqual(AttentionClock.format(seconds: 45), "45s")
        XCTAssertEqual(AttentionClock.format(seconds: 60), "1m")
        XCTAssertEqual(AttentionClock.format(seconds: 90), "1m 30s")
        XCTAssertEqual(AttentionClock.format(seconds: 3600), "1h")
        XCTAssertEqual(AttentionClock.format(seconds: 3660), "1h 1m")
        XCTAssertEqual(
            AttentionClock.remaining(until: now.addingTimeInterval(1.2), now: now),
            "2s"
        )
        XCTAssertEqual(
            AttentionClock.elapsed(since: now.addingTimeInterval(-90), now: now),
            "1m 30s"
        )
    }

    func testHistoryAutoDecidedLabelUsesDefaultOption() {
        let expired = ask(
            id: "auto-decided",
            options: ["Ship", "Hold"],
            defaultOption: "Hold",
            isExpired: true,
            status: "expired"
        )
        let open = ask(id: "open", options: ["Ship"], status: "delivered")

        XCTAssertEqual(expired.historyAutoDecidedLabel, L("Auto-decided · Hold"))
        XCTAssertTrue(expired.isAutoDecidedHistoryMessage)
        XCTAssertNil(open.historyAutoDecidedLabel)
    }
}
