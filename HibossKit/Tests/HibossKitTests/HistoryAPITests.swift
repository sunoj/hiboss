// Verifies the wire contract for opaque delta cursors and old-server decoding.
// Exports HistoryAPITests using URLProtocol to inspect actual HTTP requests.
// Depends on Foundation, XCTest, and HibossAPI; uses only synthetic credentials.

import Foundation
import XCTest
@testable import HibossKit

final class HistoryAPITests: XCTestCase {
    func testDeltaSendsCursorVerbatimAndDecodesUpdatedAt() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HistoryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let api = HibossAPI(config: ConnectionConfig(
            serverURL: URL(string: "https://history.test")!, bossToken: "synthetic"
        ), session: session)
        let page = try await api.fetchHistoryPage(updatedAfter: "2026-10-10 10:20:30.123+00:00")
        XCTAssertEqual(page.cursor, "opaque next")
        XCTAssertEqual(page.hasMore, true)
        XCTAssertEqual(page.messages.first?.updatedAt, "2026-10-10 10:20:30.123")
    }

    func testOldResponseOmitsCursorAndUpdatedAt() throws {
        let page = try JSONDecoder().decode(HistoryResponse.self, from: Data(
            #"{"messages":[],"total":0}"#.utf8
        ))
        XCTAssertNil(page.cursor)
        XCTAssertNil(page.hasMore)
    }
}

private final class HistoryURLProtocol: HTTPTestProtocol, @unchecked Sendable {

    override func startLoading() {
        let components = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        let items = components?.queryItems ?? []
        XCTAssertTrue(components?.percentEncodedQuery?.contains("%2B") == true)
        XCTAssertFalse(components?.percentEncodedQuery?.contains("+") == true)
        XCTAssertEqual(request.url?.path, "/api/boss/messages")
        XCTAssertEqual(items.first { $0.name == "direction" }?.value, "all")
        XCTAssertEqual(items.first { $0.name == "limit" }?.value, String(AppConstants.API.historyLimit))
        XCTAssertEqual(items.first { $0.name == "updated_after" }?.value, "2026-10-10 10:20:30.123+00:00")
        let payload = """
        {"messages":[{"id":"one","body":"note","direction":"agent_to_boss","status":"delivered",
        "priority":"normal","created_at":"2026-10-01T00:00:00Z","updated_at":"2026-10-10 10:20:30.123"}],
        "total":1,"cursor":"opaque next","has_more":true}
        """
        guard let url = request.url, let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil, headerFields: nil
        ) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
