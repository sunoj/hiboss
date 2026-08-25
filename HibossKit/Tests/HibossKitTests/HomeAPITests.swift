// Coverage for HibossAPI home endpoint path and HomeDashboard decoding.
// Exports: HomeAPITests verifying GET /api/boss/home.
// Dependencies: XCTest, Foundation URLProtocol, and the HibossKit API client.

import Foundation
import XCTest
@testable import HibossKit

final class HomeAPITests: XCTestCase {
    override func tearDown() {
        HomeURLProtocol.handler = nil
        super.tearDown()
    }

    func testFetchHomeUsesAuthorizedEndpointAndDecodes() async throws {
        HomeURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/boss/home")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            return try Self.response(
                for: request,
                json: #"""
                {
                  "boss": {"name": "Ming"},
                  "kpis": {
                    "activeSessions": 3, "workingSessions": 2,
                    "pendingDecisions": 1, "blockingPending": 1, "unread1h": 4
                  },
                  "activity": {
                    "days": [{"date": "2026-07-29", "posts": 2, "decisions": 1, "messages": 14}],
                    "delta": {"posts": 0.12, "decisions": -0.5, "messages": null}
                  },
                  "projects": [{
                    "name": "hiboss",
                    "sessions": {"working": 1, "waiting": 0, "blocked": 0, "idle": 0},
                    "pendingDecisions": 1,
                    "postCount7d": 5,
                    "lastPost": {"id": "p1", "body": "Shipped", "createdAt": "2026-08-01T10:00:00Z"},
                    "lastActivityAt": "2026-08-01T11:00:00Z"
                  }],
                  "attention": [{
                    "kind": "decision",
                    "messageId": "m1",
                    "sessionId": "s1",
                    "sessionLabel": "hiboss/main",
                    "project": "hiboss",
                    "priority": "high",
                    "mode": "blocking",
                    "body": "Ship?",
                    "createdAt": "2026-08-01T09:00:00Z",
                    "expiresAt": null
                  }]
                }
                """#
            )
        }
        let api = HibossAPI(config: try config(), session: session())
        let home = try await api.fetchHome()

        XCTAssertEqual(home.boss.name, "Ming")
        XCTAssertEqual(home.kpis.pendingDecisions, 1)
        XCTAssertEqual(home.activity.days.count, 1)
        XCTAssertEqual(home.activity.delta.posts, 0.12)
        XCTAssertNil(home.activity.delta.messages)
        XCTAssertEqual(home.projects.first?.name, "hiboss")
        XCTAssertEqual(home.attention.first?.kind, .decision)
        XCTAssertEqual(home.attention.first?.messageId, "m1")
    }

    private func config() throws -> ConnectionConfig {
        let serverURL = try XCTUnwrap(URL(string: "https://hiboss.example"))
        return ConnectionConfig(serverURL: serverURL, bossToken: "test-token")
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HomeURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(
        for request: URLRequest,
        json: String
    ) throws -> (HTTPURLResponse, Data) {
        let url = try XCTUnwrap(request.url)
        let response = try XCTUnwrap(
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        )
        return (response, Data(json.utf8))
    }
}

private final class HomeURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: HibossAPIError.invalidResponse)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
