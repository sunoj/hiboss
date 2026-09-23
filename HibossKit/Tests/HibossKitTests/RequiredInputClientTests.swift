// Tests pending-input pagination failure and dedicated SSE decoding.
// Exports RequiredInputClientTests; depends on URLProtocol and HibossAPI.
// Ensures an incomplete page sequence cannot become a successful snapshot.

import Foundation
import XCTest
@testable import HibossKit

final class RequiredInputClientTests: XCTestCase {
    func testSecondPageFailureRejectsTheWholePendingSet() async throws {
        let api = makeAPI("failure")
        do {
            _ = try await api.fetchRequiredInputs()
            XCTFail("A failed second page must reject the complete snapshot")
        } catch let error as HibossAPIError {
            guard case .requestFailed(status: 503, message: _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testMalformedPaginationRejectsIncompleteSnapshots() async {
        for scenario in ["missing", "empty", "repeat", "duplicate"] {
            do {
                _ = try await makeAPI(scenario).fetchRequiredInputs()
                XCTFail("Accepted malformed \(scenario) pagination")
            } catch let error as HibossAPIError {
                if scenario == "missing", case .decodingFailed(_, _) = error { continue }
                guard case .invalidResponse = error else {
                    XCTFail("Unexpected \(scenario) error: \(error)")
                    continue
                }
            } catch {
                XCTFail("Unexpected \(scenario) error: \(error)")
            }
        }
    }

    private func makeAPI(_ scenario: String) -> HibossAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PendingInputProtocol.self]
        return HibossAPI(
            config: ConnectionConfig(serverURL: URL(string: "https://example.test/\(scenario)")!, bossToken: "test"),
            session: URLSession(configuration: configuration)
        )
    }

    func testRequiredInputDecoderKeepsReadySeparateFromOptionEvents() throws {
        var parser = RequiredInputEventDecoder()
        XCTAssertNil(try parser.consume(line: "event: ready"))
        XCTAssertNil(try parser.consume(line: "data: {}"))
        XCTAssertEqual(try parser.consume(line: ""), .ready)
        XCTAssertNil(try parser.consume(line: "event: resolved"))
        XCTAssertNil(try parser.consume(line: "data: {\"id\":\"text-1\"}"))
        XCTAssertEqual(try parser.consume(line: ""), .resolved("text-1"))
    }

    func testMalformedRecognizedFramesThrow() throws {
        for name in ["message", "resolved", "ready"] {
            var parser = RequiredInputEventDecoder()
            _ = try parser.consume(line: "event: \(name)")
            _ = try parser.consume(line: "data: not-json")
            XCTAssertThrowsError(try parser.finish(), "\(name) requires a complete frame")
            XCTAssertThrowsError(try parser.consume(line: ""), "\(name) must fail the stream")
        }
    }
}

private final class PendingInputProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let cursor = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "cursor" })?.value
        let path = request.url!.path
        let status = path.contains("failure") && cursor != nil ? 503 : 200
        let message = """
          {"id":"first","body":"Choose","direction":"agent_to_boss",\
          "status":"sent","priority":"normal","created_at":"2026-09-23T00:00:00Z"}
          """
        let body: String
        if status == 503 {
            body = "unavailable"
        } else if path.contains("missing") {
            body = "{\"messages\":[]}"
        } else if cursor != nil && path.contains("empty") {
            body = "{\"messages\":[],\"next_cursor\":\"third\"}"
        } else if cursor != nil && path.contains("duplicate") {
            body = "{\"messages\":[\(message)],\"next_cursor\":null}"
        } else if cursor != nil && path.contains("repeat") {
            body = "{\"messages\":[\(message.replacingOccurrences(of: "first", with: "second"))],\"next_cursor\":\"second\"}"
        } else {
            body = "{\"messages\":[\(message)],\"next_cursor\":\"second\"}"
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
