// Coverage for HibossAPI session events history endpoint path and decoding.
// Exports: SessionStreamAPITests.
// Dependencies: XCTest, Foundation URLProtocol, HibossKit.

import Foundation
import XCTest
@testable import HibossKit

final class SessionStreamAPITests: XCTestCase {
    override func tearDown() {
        SessionURLProtocol.handler = nil
        super.tearDown()
    }

    func testFetchSessionEventsUsesCursorQuery() async throws {
        SessionURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/sessions/sess-1/events")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            let items = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(items?.first { $0.name == "after" }?.value, "10")
            XCTAssertEqual(items?.first { $0.name == "limit" }?.value, "50")
            return try Self.response(
                for: request,
                json: #"{"events":[{"id":"e11","session_id":"sess-1","sequence":11,"kind":"message","payload":{"body":"hi"},"created_at":"2026-08-14T09:00:00Z"}],"next_after":11,"resync":false}"#
            )
        }
        let api = HibossAPI(config: try config(), session: session())
        let page = try await api.fetchSessionEvents(sessionID: "sess-1", after: 10, limit: 50)
        XCTAssertEqual(page.events.first?.sequence, 11)
        XCTAssertEqual(page.nextAfter, 11)
        XCTAssertFalse(page.resync)
    }

    private func config() throws -> ConnectionConfig {
        ConnectionConfig(
            serverURL: try XCTUnwrap(URL(string: "https://hiboss.example")),
            bossToken: "test-token"
        )
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionURLProtocol.self]
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

private final class SessionURLProtocol: URLProtocol, @unchecked Sendable {
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
