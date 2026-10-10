// Covers the idle timeout of server-sent event streams versus ordinary requests.
// A stream that is quiet longer than its timeout drops and reconnects in a loop.

import XCTest
@testable import HibossKit

final class StreamTimeoutTests: XCTestCase {
    private func api() throws -> HibossAPI {
        HibossAPI(config: ConnectionConfig(
            serverURL: try XCTUnwrap(URL(string: "https://hiboss.example")), bossToken: "test-token"
        ), session: URLSession(configuration: .ephemeral))
    }

    func testStreamsOutlastTheServerKeepaliveGap() throws {
        let url = try XCTUnwrap(URL(string: "https://hiboss.example/api/boss/stream"))
        let stream = try api().authorizedRequest(url: url, method: "GET", acceptsSSE: true)
        // The server writes a keepalive every 15 s, checked after a 3 s poll: gaps reach ~18 s.
        XCTAssertGreaterThanOrEqual(stream.timeoutInterval, 3 * 15)
        XCTAssertEqual(stream.value(forHTTPHeaderField: "Accept"), "text/event-stream")
    }

    func testOrdinaryRequestsKeepTheShortTimeout() throws {
        let url = try XCTUnwrap(URL(string: "https://hiboss.example/api/boss/messages"))
        let request = try api().authorizedRequest(url: url, method: "GET")
        XCTAssertEqual(request.timeoutInterval, AppConstants.API.requestTimeout)
    }
}
