// Covers the session inventory delta cache: full read, merged deltas, removals and fallbacks.
// Also checks that HibossAPI sends the server cursor back as updated_after.
// Dependencies: XCTest, HibossKit and the in-memory HTTPTestProtocol transport.

import XCTest
@testable import HibossKit

final class SessionInventoryCacheTests: XCTestCase {
    private final class Server: @unchecked Sendable {
        var pages: [SessionInventoryPage] = []
        var failDelta = false
        private(set) var cursors: [String?] = []
        func fetch(_ cursor: String?) throws -> SessionInventoryPage {
            cursors.append(cursor)
            if cursor != nil, failDelta { throw HibossAPIError.requestFailed(status: 400, message: "bad cursor") }
            return pages.removeFirst()
        }
    }

    private func session(_ id: String, seen: String, status: String = "working") -> ProjectSession {
        ProjectSession(id: id, projectId: nil, projectSlug: nil, branch: nil, status: status, lastSeenAt: seen)
    }

    func testMergesDeltasAndRemovalsAfterOneFullRead() async throws {
        let cache = SessionInventoryCache(), server = Server()
        server.pages = [
            SessionInventoryPage(sessions: [session("a", seen: "2026-11-22 10:00:00"),
                                            session("b", seen: "2026-11-22 09:00:00")], cursor: "2026-11-22 10:00:00"),
            SessionInventoryPage(sessions: [session("b", seen: "2026-11-22 10:05:00", status: "idle"),
                                            session("c", seen: "2026-11-22 10:01:00")],
                                 removed: ["a"], cursor: "2026-11-22 10:05:00"),
        ]
        let first = try await cache.sessions(key: "k") { try server.fetch($0) }
        XCTAssertEqual(first.map(\.id), ["a", "b"])
        let second = try await cache.sessions(key: "k") { try server.fetch($0) }
        XCTAssertEqual(second.map(\.id), ["b", "c"])
        XCTAssertEqual(second.first?.status, "idle")
        XCTAssertEqual(server.cursors, [nil, "2026-11-22 10:00:00"])
    }

    func testFullReadsAgainAfterTheIntervalOrAFailedDelta() async throws {
        let cache = SessionInventoryCache(), server = Server()
        let page = SessionInventoryPage(sessions: [session("a", seen: "2026-11-22 10:00:00")], cursor: "c1")
        server.pages = [page, page, page]
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try await cache.sessions(key: "k", now: start) { try server.fetch($0) }
        _ = try await cache.sessions(key: "k", now: start + SessionInventoryCache.fullReadInterval) { try server.fetch($0) }
        server.failDelta = true
        _ = try await cache.sessions(key: "k", now: start + SessionInventoryCache.fullReadInterval + 1) { try server.fetch($0) }
        XCTAssertEqual(server.cursors, [nil, nil, "c1", nil])
    }

    func testDiscardsADeltaThatAConcurrentReadOvertook() async throws {
        let cache = SessionInventoryCache(), server = Server()
        server.pages = [SessionInventoryPage(sessions: [session("a", seen: "2026-11-22 10:00:00")], cursor: "c0")]
        _ = try await cache.sessions(key: "k") { try server.fetch($0) }
        let stale = SessionInventoryPage(sessions: [session("a", seen: "2026-11-22 10:01:00")], removed: [], cursor: "c1")
        let newer = SessionInventoryPage(sessions: [], removed: ["a"], cursor: "c2")
        let overtaken = try await cache.sessions(key: "k") { _ in
            // A second reader finishes while this delta is still in flight.
            _ = try await cache.sessions(key: "k") { _ in newer }
            return stale
        }
        XCTAssertEqual(overtaken.map(\.id), [])
        server.pages = [SessionInventoryPage(sessions: [], removed: [], cursor: "c3")]
        _ = try await cache.sessions(key: "k") { try server.fetch($0) }
        XCTAssertEqual(server.cursors.last, "c2")
    }

    func testServerWithoutCursorIsAlwaysReadInFull() async throws {
        let cache = SessionInventoryCache(), server = Server()
        let page = SessionInventoryPage(sessions: [session("a", seen: "2026-11-22 10:00:00")])
        server.pages = [page, page]
        _ = try await cache.sessions(key: "k") { try server.fetch($0) }
        _ = try await cache.sessions(key: "k") { try server.fetch($0) }
        XCTAssertEqual(server.cursors, [nil, nil])
    }

    func testAccountsDoNotShareAnInventory() {
        let url = URL(string: "https://hiboss.example")!
        XCTAssertNotEqual(SessionInventoryCache.key(for: ConnectionConfig(serverURL: url, bossToken: "one")),
                          SessionInventoryCache.key(for: ConnectionConfig(serverURL: url, bossToken: "two")))
        XCTAssertFalse(SessionInventoryCache.key(for: ConnectionConfig(serverURL: url, bossToken: "one")).contains("one"))
    }

    func testAPISendsTheCursorBackAsUpdatedAfter() async throws {
        await SessionInventoryCache.shared.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [InventoryURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let api = HibossAPI(config: ConnectionConfig(
            serverURL: try XCTUnwrap(URL(string: "https://hiboss.example")), bossToken: "inventory-token"),
            session: session)
        let first = try await api.projectSessions()
        let second = try await api.projectSessions()
        XCTAssertEqual(first.map(\.id), ["s1"])
        XCTAssertEqual(second.map(\.id), ["s2"])
        XCTAssertEqual(InventoryURLProtocol.queries, [
            "include_inactive=true", "include_inactive=true&updated_after=2026-11-22%2010:00:00",
        ])
        await SessionInventoryCache.shared.reset()
    }
}

private final class InventoryURLProtocol: HTTPTestProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var queries: [String] = []

    override func startLoading() {
        XCTAssertEqual(request.url?.path, "/api/boss/sessions")
        let query = request.url?.query ?? ""
        Self.queries.append(query)
        guard let url = request.url, let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let payload = query.contains("updated_after")
            ? #"{"sessions":[{"id":"s2","last_seen_at":"2026-11-22 10:01:00"}],"removed":["s1"],"cursor":"2026-11-22 10:01:00"}"#
            : #"{"sessions":[{"id":"s1","last_seen_at":"2026-11-22 10:00:00"}],"cursor":"2026-11-22 10:00:00"}"#
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
