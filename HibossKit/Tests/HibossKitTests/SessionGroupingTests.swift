// Unit tests for shared session grouping over HistoryMessage lists.
// Covers: recency ordering, Direct bucket, and label fallback chain.
// Dependencies: XCTest and HibossKit SessionGrouping.

import XCTest
@testable import HibossKit

final class SessionGroupingTests: XCTestCase {
    func testGroupBySessionOrdersByNewestAndBucketsDirect() {
        let olderSession = historyMessage(
            id: "a1",
            createdAt: "2026-07-15 09:00:00",
            sessionId: "sess-old",
            sessionLabel: "Older Work",
            sessionStatus: "idle"
        )
        let newerSession = historyMessage(
            id: "b1",
            createdAt: "2026-07-15 12:00:00",
            sessionId: "sess-new",
            sessionLabel: "Newer Work",
            sessionStatus: "working"
        )
        let directOlder = historyMessage(
            id: "d1",
            createdAt: "2026-07-15 10:00:00",
            sessionId: nil
        )
        let directNewer = historyMessage(
            id: "d2",
            createdAt: "2026-07-15 11:00:00",
            sessionId: nil
        )

        let groups = SessionGrouping.groupBySession([
            olderSession, directOlder, newerSession, directNewer,
        ])

        XCTAssertEqual(groups.map(\.id), ["sess-new", SessionGrouping.directSessionID, "sess-old"])
        XCTAssertEqual(groups[0].label, "Newer Work")
        XCTAssertEqual(groups[1].label, "Direct")
        XCTAssertEqual(groups[1].messages.map(\.id), [directOlder.id, directNewer.id])
        XCTAssertTrue(groups[0].isExpandedByDefault)
        XCTAssertFalse(groups[2].isExpandedByDefault)
    }

    func testGroupBySessionFallsBackThroughLabelBranchAndShortID() {
        let labeled = historyMessage(
            id: "l1",
            createdAt: "2026-07-15 12:00:00",
            sessionId: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            sessionLabel: "Labeled",
            sessionBranch: "feat/ignored"
        )
        let branched = historyMessage(
            id: "br1",
            createdAt: "2026-07-15 11:00:00",
            sessionId: "11111111-2222-3333-4444-555555555555",
            sessionBranch: "feat/session-group"
        )
        let idOnly = historyMessage(
            id: "id1",
            createdAt: "2026-07-15 10:00:00",
            sessionId: "abcdef12-3456-7890-abcd-ef1234567890"
        )

        let groups = SessionGrouping.groupBySession([labeled, branched, idOnly])

        XCTAssertEqual(groups.map(\.label), ["Labeled", "feat/session-group", "abcdef12"])
    }

    func testSessionKeyFallsBackToTargetSessionId() {
        let reply = historyMessage(
            id: "r1",
            direction: "boss_to_agent",
            createdAt: "2026-07-15 12:01:00",
            sessionId: nil,
            targetSessionId: "sess-new"
        )
        XCTAssertEqual(SessionGrouping.sessionKey(for: reply), "sess-new")
        let groups = SessionGrouping.groupBySession([
            historyMessage(id: "a1", createdAt: "2026-07-15 12:00:00", sessionId: "sess-new"),
            reply,
        ])
        XCTAssertEqual(groups.map(\.id), ["sess-new"])
        XCTAssertEqual(groups[0].messages.map(\.id), ["a1", "r1"])
    }

    private func historyMessage(
        id: MessageID,
        body: String = "Message body",
        agentName: String? = "Test Agent",
        direction: String = "agent_to_boss",
        status: String = "delivered",
        priority: String = "normal",
        createdAt: String = "2026-07-15 10:00:00",
        sessionId: String? = nil,
        targetSessionId: String? = nil,
        sessionLabel: String? = nil,
        sessionBranch: String? = nil,
        sessionStatus: String? = nil
    ) -> HistoryMessage {
        HistoryMessage(
            id: id,
            body: body,
            agentName: agentName,
            direction: direction,
            status: status,
            priority: priority,
            createdAt: createdAt,
            sessionId: sessionId,
            targetSessionId: targetSessionId,
            sessionLabel: sessionLabel,
            sessionBranch: sessionBranch,
            sessionStatus: sessionStatus
        )
    }
}
