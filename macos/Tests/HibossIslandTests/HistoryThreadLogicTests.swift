// Regression tests for folding History before search, filters, and session counts.
// Exports: HistoryThreadLogicTests over shared MessageThread fixtures.
// Dependencies: XCTest, HibossKit, and HistoryMessageLogic.

import HibossKit
import XCTest
@testable import HibossIsland

final class HistoryThreadLogicTests: XCTestCase {
    func testReplyOnlySearchKeepsTheParentAndNeverCreatesAnOrphan() {
        let history = [message("question", body: "Choose a plan"),
                       message("answer", body: "Investigate first", parent: "question")]
        let result = HistoryMessageLogic.filtered(history, segment: .all, searchText: "investigate")
        XCTAssertEqual(result.map(\.id), ["question"])
    }

    func testUnreadAndBlockingSearchTestTheParentRatherThanTheReply() {
        let history = [message("question", body: "Choose a plan", options: ["Wait"]),
                       message("answer", body: "Investigate first", parent: "question", status: "read")]
        for segment in [HistorySegment.unread, .blocking] {
            let result = HistoryMessageLogic.filtered(history, segment: segment, searchText: "investigate")
            XCTAssertEqual(result.map(\.id), ["question"])
        }
    }

    func testUnreadCountAndSessionHeaderCountThreadsRatherThanReplies() {
        let history = [message("question"), message("answer", parent: "question")]
        XCTAssertEqual(HistoryMessageLogic.unreadCount(in: history), 1)
        XCTAssertEqual(HistoryMessageLogic.groupBySession(history).first?.messages.count, 1)
    }

    func testMissingParentRemainsAStandaloneBossThread() {
        let history = [message("answer", parent: "outside-page")]
        XCTAssertEqual(HistoryMessageLogic.filtered(history, segment: .all, searchText: "")
            .map(\.id), ["answer"])
    }

    func testCompletedScopeKeepsRepliesAndTheirSharedOutcome() throws {
        let parent = message("question", status: "replied", options: ["Wait"])
        let answer = message("answer", body: "Wait", parent: "question")
        let snapshot = OverviewSnapshot(history: [parent, answer], live: nil, now: .now)
        let threads = HistoryMessageLogic.scopedThreads(snapshot: snapshot, scope: .category(.completed))
        let thread = try XCTUnwrap(threads.first)
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(thread.replies, [answer])
        XCTAssertEqual(thread.outcome, .chosen(option: "Wait", source: nil))
    }

    func testMatchingReplyCannotReturnWhenItsParentIsFilteredOut() {
        let history = [message("question", status: "read"),
                       message("answer", body: "Investigate first", parent: "question")]
        XCTAssertTrue(HistoryMessageLogic.filtered(history, segment: .unread,
            searchText: "investigate").isEmpty)
    }

    func testAutomaticSelectionUsesClockInsteadOfBossChoiceCheckmark() {
        let outcome = ThreadOutcome.autoSelected(option: " Wait ")
        XCTAssertTrue(HistoryOptionSelection.isSelected("Wait", outcome: outcome))
        XCTAssertEqual(HistoryOptionSelection.symbol("Wait", outcome: outcome), "clock.arrow.circlepath")
        XCTAssertEqual(HistoryOptionSelection.symbol("Ship", outcome: outcome), "circle")
        XCTAssertFalse(HistoryOptionSelection.isSelected("wait", outcome: outcome))
        XCTAssertEqual(HistoryOptionSelection.symbol("Wait", outcome: .chosen(option: "Wait", source: nil)),
            "checkmark.circle.fill")
        XCTAssertFalse(HistoryOptionSelection.matches("Wait", nil))
    }

    private func message(
        _ id: MessageID, body: String = "Message", parent: String? = nil,
        status: String = "delivered", options: [String] = []
    ) -> HistoryMessage {
        HistoryMessage(id: id, body: body, agentName: "Build Agent",
            direction: parent == nil ? "agent_to_boss" : "boss_to_agent",
            status: status, priority: "normal", replyTo: parent, metadata: MessageMetadata(options: options),
            createdAt: "2026-10-08T10:00:00Z", sessionId: "session")
    }
}
