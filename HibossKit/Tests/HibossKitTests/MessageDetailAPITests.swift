// Integration coverage for the targeted boss message-detail request.
// Exports: MessageDetailAPITests, validating path, timeout, and reply decoding.
// Dependencies: XCTest, Foundation URLProtocol, and HibossKit.

import Foundation
import XCTest
@testable import HibossKit

final class MessageDetailAPITests: XCTestCase {
    override func tearDown() {
        MessageDetailURLProtocol.handler = nil
        super.tearDown()
    }

    func testFetchMessageTargetsOneIDWithShortTimeout() async throws {
        XCTAssertEqual(AppConstants.API.notificationMessageTimeout, 2)
        MessageDetailURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/boss/messages/m1")
            XCTAssertEqual(request.timeoutInterval, AppConstants.API.notificationMessageTimeout)
            return try Self.response(for: request)
        }

        let api = HibossAPI(config: try config(), session: session())
        let detail = try await api.fetchMessage("m1")

        XCTAssertEqual(detail.message.body, "Ship it?")
        XCTAssertEqual(detail.replies.map(\.body), ["Approve"])
    }

    private func config() throws -> ConnectionConfig {
        ConnectionConfig(
            serverURL: try XCTUnwrap(URL(string: "https://hiboss.example")),
            bossToken: "test-token"
        )
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MessageDetailURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let response = try XCTUnwrap(
            HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)
        )
        let json = #"{"id":"m1","body":"Ship it?","direction":"agent_to_boss","status":"replied","priority":"high","created_at":"2026-09-04T00:00:00Z","replies":[{"id":"r1","body":"Approve","direction":"boss_to_agent","status":"sent","priority":"normal","reply_to":"m1","created_at":"2026-09-04T00:00:01Z"}]}"#
        return (response, Data(json.utf8))
    }
}

private final class MessageDetailURLProtocol: URLProtocol, @unchecked Sendable {
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
