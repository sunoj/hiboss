// Tests the passive feed's authenticated endpoint and live inbox-model decoder path.
// Exports: BossFeedAPITests; no live server or browser is used.
// Dependencies: XCTest, URLProtocol, and HibossKit.

import Foundation
import XCTest
@testable import HibossKit

final class BossFeedAPITests: XCTestCase {
    static let payload = #"{"id":"plain-1","body":"ping","agent_name":"Agent","direction":"agent_to_boss","status":"pending","priority":"normal","created_at":"2026-09-11 12:00:00","session_id":"session-1","session_label":"Build","metadata":null}"#

    func testFeedUsesPassiveEndpointAndDecodesInboxShapeBeforeStreamCloses() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let api = HibossAPI(config: ConnectionConfig(
            serverURL: try XCTUnwrap(URL(string: "https://hiboss.example/api-base")),
            bossToken: "test-token"
        ), session: session)
        let stream = await api.feedStream()
        var iterator = stream.makeAsyncIterator()
        let message = try await iterator.next()
        XCTAssertEqual(message?.id, "plain-1")
        XCTAssertEqual(message?.direction, "agent_to_boss")
        XCTAssertEqual(message?.sessionId, "session-1")
        XCTAssertEqual(message?.sessionLabel, "Build")
        XCTAssertEqual(message?.options, [])
    }

    func testDecoderIgnoresKeepalivesOtherEventsAndMalformedData() {
        var decoder = BossFeedDecoder()
        XCTAssertNil(decoder.consume(line: ": keepalive"))
        XCTAssertNil(decoder.consume(line: "event: resolved"))
        XCTAssertNil(decoder.consume(line: "data: " + Self.payload))
        XCTAssertNil(decoder.consume(line: "data: invalid"))
        XCTAssertNil(decoder.consume(line: "event: message"))
        XCTAssertEqual(decoder.consume(line: "data: " + Self.payload)?.body, "ping")
    }

    func testDecoderPreservesOptionsAndBossDirectionForConsumerFiltering() throws {
        var decoder = BossFeedDecoder()
        let payload = Self.payload.replacingOccurrences(of: "agent_to_boss", with: "boss_to_agent")
            .replacingOccurrences(of: "\"metadata\":null", with: "\"metadata\":{\"options\":[\"Yes\"]}")
        let message = try XCTUnwrap(decoder.consume(line: "data: " + payload))
        XCTAssertEqual(message.options, ["Yes"])
        XCTAssertEqual(message.direction, "boss_to_agent")
    }
}

private final class FeedURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        XCTAssertEqual(request.url?.path, "/api-base/api/boss/stream")
        XCTAssertEqual(request.url?.query, "feed=true")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        guard let url = request.url, let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "text/event-stream"]
        ) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let event = ": keepalive\n\nevent: message\ndata: \(BossFeedAPITests.payload)\n\n"
        client?.urlProtocol(self, didLoad: Data(event.utf8))
        // Deliberately keep the response open: notification delivery cannot wait for EOF.
    }

    override func stopLoading() {}
}
