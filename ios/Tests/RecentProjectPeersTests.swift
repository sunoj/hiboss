// Recent-peer boundary, project isolation, deduplication, order and preview coverage.
// Exports RecentProjectPeersTests; depends on XCTest and iOS project presentation.

import HibossKit
import XCTest
@testable import HiBoss

final class RecentProjectPeersTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testIncludes24HourBoundaryAndExcludesOlderFutureAndSelf() {
        let current = session("self", age: 1)
        let peers = RecentProjectPeers.all(current: current, sessions: [current,
            session("boundary", age: 86400), session("old", age: 86401), session("future", age: -1)],
            messages: [], now: now)
        XCTAssertEqual(peers.map(\.id), ["boundary"])
    }

    func testDeduplicatesByIdKeepingNewestAndSortsNewestFirst() {
        let peers = RecentProjectPeers.all(current: session("self", age: 0), sessions: [
            session("a", age: 90), session("b", age: 20), session("a", age: 10),
        ], messages: [], now: now)
        XCTAssertEqual(peers.map(\.id), ["a", "b"])
        XCTAssertEqual(peers.first?.activityDate, now.addingTimeInterval(-10))
    }

    func testPreviewCapsAtFiveAndFullListRetainsAllRecentPeers() {
        let peers = RecentProjectPeers.all(current: session("self", age: 0),
            sessions: (0..<8).map { session("peer-\($0)", age: Double($0)) }, messages: [], now: now)
        XCTAssertEqual(peers.count, 8)
        XCTAssertEqual(RecentProjectPeers.preview(peers).map(\.id), (0..<5).map { "peer-\($0)" })
    }

    func testNewestMessageFallbackAndInventoryTimestampTakesPrecedence() {
        let peers = RecentProjectPeers.all(current: session("self", age: 0), sessions: [
            session("missing", age: nil), session("malformed", age: nil, timestamp: "invalid"),
            session("stale", age: 90000), session("unknown", age: nil),
        ], messages: [message("missing", age: 90000), message("missing", age: 10),
                      message("malformed", age: 20), message("stale", age: 1)], now: now)
        XCTAssertEqual(peers.map(\.id), ["missing", "malformed"])
    }

    func testOtherProjectsAndUnassignedSessionsAreExcluded() {
        let peers = RecentProjectPeers.all(current: session("self", age: 0), sessions: [
            session("same", age: 1), session("other", age: 2, project: "other"),
            session("unassigned", age: 3, project: nil),
        ], messages: [], now: now)
        XCTAssertEqual(peers.map(\.id), ["same"])
    }

    func testSessionLabelUsesNicknameAndIgnoresBlankNickname() {
        XCTAssertEqual(session("a", age: 1, nickname: "otter-2").namedLabel, "release · otter-2")
        XCTAssertEqual(session("a", age: 1, nickname: "  ").namedLabel, "release")
        XCTAssertEqual(session("a", age: 1).namedLabel, "release")
    }

    private func session(_ id: String, age: TimeInterval?, timestamp: String? = nil,
                         project: String? = "hiboss", nickname: String? = nil) -> ProjectSession {
        ProjectSession(id: id, projectId: project, projectSlug: project, branch: nil,
                       label: "release", lastSeenAt: timestamp ?? age.map {
                           now.addingTimeInterval(-$0).ISO8601Format()
                       }, nickname: nickname)
    }

    private func message(_ session: String, age: TimeInterval) -> HistoryMessage {
        HistoryMessage(id: MessageID(rawValue: "\(session)-\(age)"), body: "Update",
                       direction: "agent_to_boss", status: "delivered", priority: "normal",
                       createdAt: now.addingTimeInterval(-age).ISO8601Format(), sessionId: session)
    }
}
