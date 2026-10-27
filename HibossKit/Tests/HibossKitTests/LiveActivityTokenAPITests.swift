// Integration coverage for registering a Live Activity push token with the server.
// Exports: LiveActivityTokenAPITests, validating path, method and body.
// Dependencies: XCTest, Foundation URLProtocol, and HibossKit.

import Foundation
import XCTest
@testable import HibossKit

final class LiveActivityTokenAPITests: XCTestCase {
    override func tearDown() {
        LiveActivityTokenURLProtocol.handler = nil
        super.tearDown()
    }

    func testRegistersTokenForOneMessage() async throws {
        nonisolated(unsafe) var body: [String: String] = [:]
        LiveActivityTokenURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/boss/devices/live-activities")
            body = try JSONDecoder().decode([String: String].self, from: Self.body(of: request))
            return try Self.response(for: request, status: 204)
        }
        let api = HibossAPI(config: try config(),
            session: HTTPTestSupport.session(for: LiveActivityTokenURLProtocol.self))

        try await api.registerLiveActivityToken(messageID: "m1", token: "abcd", environment: "sandbox")

        XCTAssertEqual(body, ["messageId": "m1", "activityToken": "abcd", "environment": "sandbox"])
    }

    func testConflictThrows() async throws {
        LiveActivityTokenURLProtocol.handler = { try Self.response(for: $0, status: 409) }
        let api = HibossAPI(config: try config(),
            session: HTTPTestSupport.session(for: LiveActivityTokenURLProtocol.self))
        do {
            try await api.registerLiveActivityToken(messageID: "m1", token: "abcd", environment: "sandbox")
            XCTFail("409 must throw")
        } catch {}
    }

    private func config() throws -> ConnectionConfig {
        ConnectionConfig(serverURL: try XCTUnwrap(URL(string: "https://hiboss.example")), bossToken: "test-token")
    }

    private static func body(of request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private static func response(for request: URLRequest, status: Int) throws -> (HTTPURLResponse, Data) {
        let response = try XCTUnwrap(
            HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: status, httpVersion: nil, headerFields: nil)
        )
        return (response, Data())
    }
}

private final class LiveActivityTokenURLProtocol: HTTPTestProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: HibossAPIError.invalidResponse)
            return
        }
        complete { try handler(request) }
    }
}
