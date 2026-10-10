// Verifies recent peers, inventory timestamps, duplicate selection, and nickname labels.
// Covers: inclusive 24-hour cutoff, missing activity, project scope, self exclusion, and cap.
// Dependencies: XCTest, HibossKit fixtures, and production SessionPeers/SessionContext.

import HibossKit
import XCTest
@testable import HibossIsland

final class SessionPeersTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testInclusive24HourWindowExcludesOldFutureAndUnknownActivity() {
        let peers = recent([session("edge", age: 86_400), session("old", age: 86_401),
            session("fresh", age: 1), session("future", age: -1), session("unknown", age: nil)])
        XCTAssertEqual(peers.map(\.id), ["fresh", "edge"])
    }

    func testDedupeKeepsNewestEntrySortsAndCapsFiveUntilShowAll() {
        let peers = recent((1...7).map { session("peer-\($0)", age: Double($0)) }
            + [session("peer-1", age: 100)])
        XCTAssertEqual(peers.map(\.id), (1...7).map { "peer-\($0)" })
        XCTAssertEqual(peers.first?.session.lastSeenAt, session("peer-1", age: 1).lastSeenAt)
        XCTAssertEqual(SessionPeers.visible(peers, showAll: false).map(\.id),
            (1...5).map { "peer-\($0)" })
        XCTAssertEqual(SessionPeers.visible(peers, showAll: true).count, 7)
    }

    func testExcludesSelfAndUnrelatedProjectEvenWhenSlugMatches() {
        let peers = recent([session("self", age: 0), session("same", age: 5),
            session("other", age: 1, project: "other")])
        XCTAssertEqual(peers.map(\.id), ["same"])
    }

    func testMissingProjectIDFallsBackToMatchingSlug() {
        let missing = ProjectSession(id: "slug-only", projectId: nil, projectSlug: "hiboss", branch: nil,
            lastSeenAt: AttentionTestSupport.iso(now.addingTimeInterval(-10)))
        XCTAssertEqual(recent([missing]).map(\.id), ["slug-only"])
    }

    func testContextPeersExcludeStaleSessionsAndDuplicateIDs() {
        let context = SessionContext(id: "self", snapshot: snapshot([]), inventory: [
            session("self", age: 0), session("peer", age: 30), session("old", age: 90_000),
            session("peer", age: 60)])
        XCTAssertEqual(context.peers.map(\.id), ["peer"])
    }

    func testNewestMessageFallbackAndInventoryTimestampTakesPrecedence() {
        let peers = recent([session("fallback", age: nil), session("malformed", age: nil,
            rawTimestamp: "invalid"), session("old", age: 90_000)], history: [
                message("fallback", age: 90_000), message("fallback", age: 20),
                message("malformed", age: 10), message("old", age: 0)])
        XCTAssertEqual(peers.map(\.id), ["malformed", "fallback"])
        XCTAssertEqual(peers.last?.lastActivity, now.addingTimeInterval(-20))
    }

    /// The inspector ranks peers on every redraw, and the server sends SQLite timestamps.
    /// Parsing those without a cache, per peer per redraw, made the inspector stall.
    func testRepeatedRankingOfSQLiteTimestampsStaysFast() {
        let inventory = (0..<1_000).map { index in
            let iso = AttentionTestSupport.iso(now.addingTimeInterval(-Double(index)))
            let sql = iso.replacingOccurrences(of: "T", with: " ").replacingOccurrences(of: "Z", with: "")
            return session("peer-\(index)", age: nil, rawTimestamp: String(sql.prefix(19)))
        }
        let started = Date()
        for _ in 0..<20 { XCTAssertEqual(recent(inventory).count, 1_000) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
    }

    func testSessionLabelsUseExplicitLabelAndOptionalTrimmedNickname() {
        let named = ProjectSession(id: "self", projectId: "project", projectSlug: "hiboss", branch: "main",
            label: "hiboss/custom", nickname: " otter-2 ")
        XCTAssertEqual(named.namedLabel, "hiboss/custom · otter-2")
        let unnamed = ProjectSession(id: "self", projectId: nil, projectSlug: "hiboss", branch: "main",
            nickname: " ")
        XCTAssertEqual(unnamed.namedLabel, "hiboss/main")
        let context = SessionContext(id: "self", snapshot: snapshot([]), inventory: [named])
        XCTAssertEqual(context.title, "hiboss/custom · otter-2")
    }

    private func recent(_ inventory: [ProjectSession], history: [HistoryMessage] = []) -> [SessionPeer] {
        SessionPeers.recent(context: SessionContext(id: "self", snapshot: snapshot(history),
            inventory: [session("self", age: 0)] + inventory), now: now)
    }

    private func snapshot(_ history: [HistoryMessage]) -> OverviewSnapshot {
        OverviewSnapshot(history: history, live: nil, now: now)
    }

    private func session(_ id: String, age: Double?, project: String = "project",
                         rawTimestamp: String? = nil) -> ProjectSession {
        ProjectSession(id: id, projectId: project, projectSlug: "hiboss", branch: "main",
            lastSeenAt: rawTimestamp ?? age.map { AttentionTestSupport.iso(now.addingTimeInterval(-$0)) })
    }

    private func message(_ session: String, age: Double) -> HistoryMessage {
        HistoryMessage(id: MessageID(rawValue: UUID().uuidString), body: "Update", agentName: "Agent",
            direction: "agent_to_boss", status: "delivered", priority: "normal",
            createdAt: AttentionTestSupport.iso(now.addingTimeInterval(-age)), sessionId: session)
    }
}
