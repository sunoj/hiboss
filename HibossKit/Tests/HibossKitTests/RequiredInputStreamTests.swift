// Exercises required-input readiness through Foundation's actual async byte transport.
// Exports RequiredInputStreamTests; uses a synthetic URLProtocol without credentials.
// Keeps the response open so readiness cannot depend on stream rotation or EOF.

import Foundation
import XCTest
@testable import HibossKit

final class RequiredInputStreamTests: XCTestCase {
    func testReadyArrivesBeforeTheStreamCloses() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReadyStreamProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let api = HibossAPI(
            config: ConnectionConfig(serverURL: URL(string: "https://example.test")!, bossToken: "test"),
            session: session
        )
        let ready = expectation(description: "initial required-input readiness")
        let consumer = Task {
            let stream = await api.requiredInputStream()
            do {
                for try await event in stream {
                    XCTAssertEqual(event, .ready)
                    ready.fulfill()
                    return
                }
            } catch {
                if !Task.isCancelled { XCTFail("Readiness failed: \(error)") }
            }
        }
        await fulfillment(of: [ready], timeout: 2)
        consumer.cancel()
        await consumer.value
    }

    func testFragmentedUnicodeFramesResolveInOrderWithoutDuplicates() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReadyStreamProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let api = HibossAPI(
            config: ConnectionConfig(serverURL: URL(string: "https://example.test/events")!, bossToken: "test"),
            session: session
        )
        let delivered = expectation(description: "complete required-input frames")
        let consumer = Task {
            var events: [RequiredInputEvent] = []
            do {
                for try await event in await api.requiredInputStream() {
                    events.append(event)
                    if events.count == 3 {
                        XCTAssertEqual(events, [.ready, .message(ReadyStreamProtocol.message), .resolved("ask")])
                        delivered.fulfill()
                        return
                    }
                }
            } catch {
                if !Task.isCancelled { XCTFail("Frame delivery failed: \(error)") }
            }
        }
        await fulfillment(of: [delivered], timeout: 2)
        consumer.cancel()
        await consumer.value
    }
}

private final class ReadyStreamProtocol: URLProtocol, @unchecked Sendable {
    static let message = HistoryMessage(
        id: "ask", body: "Choose 🏠?", direction: "agent_to_boss", status: "sent",
        priority: "normal", mode: "blocking", createdAt: "2026-10-11T00:00:00Z"
    )
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("event: ready\r\ndata: {}\r\n\r\n".utf8))
        if request.url?.path.hasPrefix("/events/") == true {
            let payload = String(decoding: try! JSONEncoder().encode(Self.message), as: UTF8.self)
            let frames = ": keepalive\n\nevent: message\ndata: \(payload)\n\n"
                + "event: resolved\ndata: {\"id\":\"ask\"}\n\n"
            for byte in frames.utf8 {
                client?.urlProtocol(self, didLoad: Data([byte]))
            }
        }
    }

    override func stopLoading() {}
}
