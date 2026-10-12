// Unit tests for island/window agreement, live merge, clock, and auto-decided history.
// Covers: IslandAttention front item, ordinary live questions, and History auto-decided labels.
// Dependencies: XCTest, HibossKit fixtures, AttentionTestSupport.

import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class AttentionIslandAgreementTests: XCTestCase {
    private let now = AttentionTestSupport.now
    private func iso(_ date: Date) -> String { AttentionTestSupport.iso(date) }
    private func snapshot(requiredInputs: [HistoryMessage], live: OptionMessage? = nil,
                          now: Date) -> TodaySnapshot {
        TodaySnapshot(history: [], requiredInputs: TodayProjection.merge(history: requiredInputs, live: live),
            health: .live(checkedAt: now), coverageComplete: true, now: now)
    }

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
        let front = snapshot(requiredInputs: history, live: live, now: now).decisions.first?.id
        let island = IslandAttention.presentation(
            snapshot: snapshot(requiredInputs: history, now: now))

        XCTAssertEqual(front, "blocked")
        XCTAssertEqual(island?.message.id, front)
    }

    func testServerListedAutoDecisionAppearsWithoutHistory() {
        let live = OptionMessage(
            id: "live-auto",
            body: "Pick soon",
            agentName: "Agent",
            metadata: MessageMetadata(options: ["A", "B"], defaultOption: "B"),
            expiresAt: iso(now.addingTimeInterval(45)),
            sessionLabel: "proj/main"
        )

        let ranked = snapshot(requiredInputs: [], live: live, now: now).decisions
        let island = IslandAttention.presentation(
            snapshot: snapshot(requiredInputs: [], live: live, now: now))

        XCTAssertEqual(ranked.map(\.id.rawValue), ["live-auto"])
        XCTAssertEqual(island?.message.id.rawValue, "live-auto")
    }

    func testIslandAndWindowIncludeServerListedOrdinaryQuestions() {
        let live = OptionMessage.fixture(id: "plain", options: ["Continue"])
        let island = IslandAttention.presentation(
            snapshot: snapshot(requiredInputs: [], live: live, now: now))

        XCTAssertEqual(island?.message.id.rawValue, "plain")
        XCTAssertEqual(island?.item?.group, .priority)
        XCTAssertEqual(snapshot(requiredInputs: [], live: live, now: now).decisions.map(\.id), ["plain"])
    }

    func testOlderSharedDecisionKeepsIslandOverNewLiveQuestion() {
        let older = ask(id: "older", options: ["Ok"], createdAt: iso(now.addingTimeInterval(-300)))
        let live = OptionMessage.fixture(id: "live", options: ["Ship"])

        let island = IslandAttention.presentation(
            snapshot: snapshot(requiredInputs: [older], live: live, now: now))

        XCTAssertEqual(snapshot(requiredInputs: [older], live: live, now: now).decisions.first?.id, "older")
        XCTAssertEqual(island?.message.id.rawValue, "older")
        XCTAssertEqual(island?.item?.group, .priority)
    }

    func testUrgentQuestionStillLeadsIslandOverLiveQuestion() {
        let blocked = ask(id: "blocked", options: ["Approve"], sessionStatus: "waiting")
        let live = OptionMessage.fixture(id: "live", options: ["Ship"])

        let island = IslandAttention.presentation(
            snapshot: snapshot(requiredInputs: [blocked], live: live, now: now))

        XCTAssertEqual(island?.message.id.rawValue, "blocked")
    }

    func testClockFormatsRemainingAndElapsed() {
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(AttentionClock.format(seconds: 0, locale: en), "0s")
        XCTAssertEqual(AttentionClock.format(seconds: 45, locale: en), "45s")
        XCTAssertEqual(AttentionClock.format(seconds: 60, locale: en), "1m")
        XCTAssertEqual(AttentionClock.format(seconds: 90, locale: en), "1m 30s")
        XCTAssertEqual(AttentionClock.format(seconds: 3600, locale: en), "1h")
        XCTAssertEqual(AttentionClock.format(seconds: 3660, locale: en), "1h 1m")
        XCTAssertEqual(AttentionClock.format(seconds: 7199, locale: en), "1h 59m")
        XCTAssertEqual(AttentionClock.format(seconds: 180_000, locale: en), "2d 2h")
        XCTAssertEqual(
            AttentionClock.remaining(until: now.addingTimeInterval(1.2), now: now, locale: en),
            "2s"
        )
        XCTAssertEqual(
            AttentionClock.elapsed(since: now.addingTimeInterval(-90), now: now, locale: en),
            "1m 30s"
        )
    }

    func testClockUsesTheLocaleUnitNames() {
        XCTAssertEqual(AttentionClock.format(seconds: 90, locale: Locale(identifier: "ja")), "1分30秒")
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
