// Regression tests for the workspace's actionable and completed decision sets.
// Exports: WorkspaceDecisionTests; exercises pure projections without launching UI.
// Dependencies: XCTest, HibossKit, AttentionTestSupport, and OverviewSnapshot.

import XCTest
import HibossKit
@testable import HibossIsland

final class WorkspaceDecisionTests: XCTestCase {
    private let now = AttentionTestSupport.now

    func testOrdinaryQuestionDoesNotDependOnSessionHeartbeat() {
        let question = AttentionTestSupport.ask(id: "normal", options: ["Review"], sessionStatus: "working")
        let snapshot = OverviewSnapshot(history: [question], live: nil, now: now)
        XCTAssertEqual(snapshot.count(.needsYou), 1)
        XCTAssertEqual(snapshot.count(.waiting), 1)
    }

    func testExpiredPriorityQuestionLeavesAttentionAndEntersCompleted() {
        let question = AttentionTestSupport.ask(id: "expired", priority: "critical", options: ["Ship"],
            defaultOption: "Ship", expiresAt: AttentionTestSupport.iso(now))
        let snapshot = OverviewSnapshot(history: [question], live: nil, now: now)
        XCTAssertEqual(snapshot.count(.needsYou), 0)
        XCTAssertEqual(snapshot.count(.urgent), 0)
        XCTAssertEqual(snapshot.count(.completed), 1)
    }

    func testLiveOrdinaryQuestionAppearsBeforeHistoryArrives() {
        let live = OptionMessage(id: "live", body: "Review?", metadata: MessageMetadata(options: ["Yes", "No"]))
        XCTAssertEqual(OverviewSnapshot(history: [], live: live, now: now).count(.needsYou), 1)
    }

    func testDeadlineWithoutDefaultIsStillActionableUntilExpiry() {
        let question = AttentionTestSupport.ask(id: "timed", options: ["Review"],
            expiresAt: AttentionTestSupport.iso(now.addingTimeInterval(30)))
        let before = OverviewSnapshot(history: [question], live: nil, now: now)
        let after = OverviewSnapshot(history: [question], live: nil, now: now.addingTimeInterval(30))
        XCTAssertEqual(before.count(.needsYou), 1)
        XCTAssertEqual(before.count(.automatic), 0)
        XCTAssertEqual(after.count(.needsYou), 0)
        XCTAssertEqual(after.count(.completed), 1)
    }

    func testExpiredNotificationWithoutChoicesDoesNotBecomeCompletedDecision() {
        let message = AttentionTestSupport.ask(id: "notice", options: [],
            expiresAt: AttentionTestSupport.iso(now.addingTimeInterval(-1)))
        XCTAssertEqual(OverviewSnapshot(history: [message], live: nil, now: now).count(.completed), 0)
    }

    func testHistoryReplyStopsAtDeadlineWithoutClaimingAutomaticExecution() {
        let question = AttentionTestSupport.ask(id: "history", options: ["Ship"], defaultOption: "Ship",
            expiresAt: AttentionTestSupport.iso(now.addingTimeInterval(30)))
        XCTAssertTrue(question.canAnswerHistory(at: now))
        XCTAssertFalse(question.canAnswerHistory(at: now.addingTimeInterval(30)))
        XCTAssertNil(question.historyAutoDecidedLabel)
    }

    func testPeerMessagesWithChoicesNeverBecomeBossDecisions() {
        let message = HistoryMessage(id: "peer", body: "Peer question", agentName: "Agent",
            direction: "agent_to_agent", status: "delivered", priority: "high",
            metadata: MessageMetadata(options: ["Yes"]), createdAt: AttentionTestSupport.iso(now))
        XCTAssertEqual(OverviewSnapshot(history: [message], live: nil, now: now).count(.needsYou), 0)
        XCTAssertFalse(message.canAnswerHistory(at: now))
    }
}
