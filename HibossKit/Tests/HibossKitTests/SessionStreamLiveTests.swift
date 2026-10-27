// Coverage for the session SSE stream through the real HibossAPI network path.
// Exports: SessionStreamLiveTests.
// Dependencies: XCTest, Foundation URLProtocol, HibossKit.

import Foundation
import XCTest
@testable import HibossKit

final class SessionStreamLiveTests: XCTestCase {
    override func tearDown() {
        HeldOpenSSEProtocol.chunks = []
        HeldOpenSSEProtocol.lastEventID = nil
        super.tearDown()
    }

    func testFramesArriveWhileStreamStaysOpen() async throws {
        let event = #"{"id":"e4","session_id":"sess-1","sequence":4,"kind":"message","created_at":"2026-08-14T09:00:00Z"}"#
        HeldOpenSSEProtocol.chunks = [
            ": keepalive\n\n",
            "id: 4\nevent: session_event\ndata: \(event)\n\n",
            "event: resync\ndata: {\"resync\":true}\n\n",
            ": keepalive\n\n",
        ]
        let api = HibossAPI(config: try config(),
            session: HTTPTestSupport.session(for: HeldOpenSSEProtocol.self))
        let frames = FrameLog()
        let received = expectation(description: "open, event and resync while open")
        let consumer = Task {
            for try await frame in await api.sessionEventStream(sessionID: "sess-1", after: 3) {
                if await frames.append(frame) == 3 { received.fulfill() }
            }
        }
        await fulfillment(of: [received], timeout: 3)
        consumer.cancel()

        let log = await frames.items
        XCTAssertEqual(log.count, 3)
        guard log.count == 3 else { return }
        guard case .open = log[0] else { return XCTFail("expected .open first") }
        guard case let .event(decoded) = log[1] else { return XCTFail("expected session_event") }
        XCTAssertEqual(decoded.sequence, 4)
        guard case .resync = log[2] else { return XCTFail("expected resync") }
        XCTAssertEqual(HeldOpenSSEProtocol.lastEventID, "3")
    }

    private func config() throws -> ConnectionConfig {
        ConnectionConfig(
            serverURL: try XCTUnwrap(URL(string: "https://hiboss.example")),
            bossToken: "test-token"
        )
    }


}

private actor FrameLog {
    private(set) var items: [SessionStreamFrame] = []

    func append(_ frame: SessionStreamFrame) -> Int {
        items.append(frame)
        return items.count
    }
}

/// Sends the SSE chunks and never finishes loading, like a live server stream.
private final class HeldOpenSSEProtocol: HTTPTestProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var chunks: [String] = []
    nonisolated(unsafe) static var lastEventID: String?

    override func startLoading() {
        Self.lastEventID = request.value(forHTTPHeaderField: "Last-Event-ID")
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
              ) else {
            client?.urlProtocol(self, didFailWithError: HibossAPIError.invalidResponse)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in Self.chunks {
            client?.urlProtocol(self, didLoad: Data(chunk.utf8))
        }
    }
}
