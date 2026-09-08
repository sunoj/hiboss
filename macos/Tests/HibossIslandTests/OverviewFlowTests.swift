// Verifies overview counts, category routing, and session isolation against real message models.
// Exports: OverviewFlowTests covering the overview-to-list contract and resolved transitions.
// Dependencies: XCTest, HibossKit, OverviewSnapshot, AttentionTestSupport.

import XCTest
import HibossKit
@testable import HibossIsland

final class OverviewFlowTests: XCTestCase {
    private let now = AttentionTestSupport.now

    func testDashboardUsesTheDecisionQueueWithoutCompletedMessages() {
        let snapshot = OverviewSnapshot(history: fixtures(), live: nil, now: now)
        XCTAssertEqual(snapshot.title(for: .dashboard), "Dashboard")
        XCTAssertEqual(snapshot.messages(for: .dashboard).map(\.id), snapshot.attention.map(\.id))
        XCTAssertFalse(snapshot.messages(for: .dashboard).contains { $0.id == "done" })
    }

    func testEveryTileCountMatchesItsDestination() {
        let snapshot = OverviewSnapshot(history: fixtures(), live: nil, now: now)
        for category in OverviewCategory.allCases {
            XCTAssertEqual(snapshot.count(category), snapshot.messages(for: .category(category)).count)
        }
        XCTAssertEqual(snapshot.count(.needsYou), 3)
        XCTAssertEqual(snapshot.count(.automatic), 1)
        XCTAssertEqual(snapshot.count(.waiting), 1)
        XCTAssertEqual(snapshot.count(.urgent), 1)
        XCTAssertEqual(snapshot.count(.all), 4)
        XCTAssertEqual(snapshot.count(.completed), 1)
    }

    func testResolvedQuestionLeavesAttentionAndEntersCompleted() {
        let pending = AttentionTestSupport.ask(id: "question", options: ["Ship"], sessionStatus: "waiting")
        let resolved = AttentionTestSupport.ask(id: "question", options: ["Ship"], status: "replied")
        let before = OverviewSnapshot(history: [pending], live: nil, now: now)
        let after = OverviewSnapshot(history: [resolved], live: nil, now: now)
        XCTAssertEqual(before.count(.needsYou), 1)
        XCTAssertEqual(before.count(.completed), 0)
        XCTAssertEqual(after.count(.needsYou), 0)
        XCTAssertEqual(after.messages(for: .category(.completed)).map(\.id), ["question"])
    }

    func testLiveQuestionIsCountedOnceAndResolvedHistoryWins() {
        let live = OptionMessage(id: "live", body: "Ship?", agentName: "Agent",
            metadata: MessageMetadata(options: ["Ship"], defaultOption: "Ship"),
            expiresAt: AttentionTestSupport.iso(now.addingTimeInterval(60)))
        let resolved = AttentionTestSupport.ask(id: "live", options: ["Ship"], status: "replied")
        XCTAssertEqual(OverviewSnapshot(history: [], live: live, now: now).count(.automatic), 1)
        let snapshot = OverviewSnapshot(history: [resolved], live: live, now: now)
        XCTAssertEqual(snapshot.count(.all), 1)
        XCTAssertEqual(snapshot.count(.needsYou), 0)
        XCTAssertEqual(snapshot.count(.completed), 1)
    }

    func testSessionRowsUseStableIDsEvenWhenLabelsMatch() {
        let first = AttentionTestSupport.ask(id: "one", options: [], sessionLabel: "same/main")
        let second = AttentionTestSupport.ask(id: "two", options: [], sessionLabel: "same/main")
        let snapshot = OverviewSnapshot(history: [first, second], live: nil, now: now)
        XCTAssertEqual(snapshot.sessions.count, 2)
        XCTAssertEqual(snapshot.messages(for: .session("one")).map(\.id), ["one"])
        XCTAssertEqual(snapshot.messages(for: .session("two")).map(\.id), ["two"])
    }

    func testBossReplyIsInSessionAndAllButDoesNotInflateCompletedCount() {
        let reply = HistoryMessage(id: "reply", body: "Approved", agentName: nil,
            direction: "boss_to_agent", status: "replied", priority: "normal",
            createdAt: AttentionTestSupport.iso(now), targetSessionId: "session")
        let snapshot = OverviewSnapshot(history: [reply], live: nil, now: now)
        XCTAssertEqual(snapshot.count(.all), 1)
        XCTAssertEqual(snapshot.count(.completed), 0)
        XCTAssertEqual(snapshot.messages(for: .session("session")).map(\.id), ["reply"])
    }

    func testHighPriorityIncludesTimedAndBlockedQuestions() {
        let timed = AttentionTestSupport.ask(id: "timed", priority: "high", options: ["Ship"],
            defaultOption: "Ship", expiresAt: AttentionTestSupport.iso(now.addingTimeInterval(60)))
        let blocked = AttentionTestSupport.ask(id: "blocked", priority: "critical", options: ["Review"],
            sessionStatus: "waiting")
        let snapshot = OverviewSnapshot(history: [timed, blocked], live: nil, now: now)
        XCTAssertEqual(snapshot.count(.urgent), 2)
        XCTAssertEqual(snapshot.count(.automatic), 1)
        XCTAssertEqual(snapshot.count(.waiting), 1)
    }

    private func fixtures() -> [HistoryMessage] {
        [
            AttentionTestSupport.ask(id: "auto", options: ["Ship"], defaultOption: "Ship",
                expiresAt: AttentionTestSupport.iso(now.addingTimeInterval(90))),
            AttentionTestSupport.ask(id: "blocked", options: ["Approve"], sessionStatus: "waiting"),
            AttentionTestSupport.ask(id: "urgent", priority: "high", options: ["Review"]),
            AttentionTestSupport.ask(id: "done", options: ["Ship"], status: "replied"),
        ]
    }
}
