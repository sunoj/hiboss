// Coverage for HibossAPI preference endpoint request and response handling.
// Exports: HibossAPIPreferencesTests verifying fetch and update preferences.
// Dependencies: XCTest, Foundation URLProtocol, and the HibossKit API client.

import Foundation
import XCTest
@testable import HibossKit

final class HibossAPIPreferencesTests: XCTestCase {
    override func tearDown() {
        PreferencesURLProtocol.handler = nil
        super.tearDown()
    }

    func testFetchPreferencesUsesAuthorizedBossEndpoint() async throws {
        PreferencesURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/boss/me/preferences")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            return try Self.response(
                for: request,
                json: #"{"routing":{"critical":["api"]},"quiet_hours":null}"#
            )
        }
        let api = HibossAPI(config: try config(), session: session())

        let preferences = try await api.fetchPreferences()

        XCTAssertEqual(preferences.routing?[.critical], [.api])
        XCTAssertNil(preferences.quietHours)
    }

    func testUpdatePreferencesUsesAuthorizedBossEndpoint() async throws {
        PreferencesURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.path, "/api/boss/me/preferences")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            let body = try Self.bodyData(from: request)
            let preferences = try JSONDecoder().decode(BossPreferences.self, from: body)
            XCTAssertEqual(preferences.routing?[.high], [.telegram])
            return try Self.response(
                for: request,
                json: #"{"routing":{"critical":["api"],"high":["telegram"]}}"#
            )
        }
        let api = HibossAPI(config: try config(), session: session())

        let preferences = try await api.updatePreferences(
            BossPreferences(routing: [.high: [.telegram]])
        )

        XCTAssertEqual(preferences.routing?[.critical], [.api])
        XCTAssertEqual(preferences.routing?[.high], [.telegram])
    }

    private func config() throws -> ConnectionConfig {
        let serverURL = try XCTUnwrap(URL(string: "https://hiboss.example"))
        return ConnectionConfig(serverURL: serverURL, bossToken: "test-token")
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PreferencesURLProtocol.self]
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

    private static func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                throw stream.streamError ?? HibossAPIError.invalidResponse
            }
            if count == 0 {
                return data
            }
            data.append(buffer, count: count)
        }
    }
}

private final class PreferencesURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

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
