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
            return try HTTPTestSupport.response(
                for: request,
                json: #"{"routing":{"critical":["api"]},"quiet_hours":null}"#
            )
        }
        let api = HibossAPI(config: try config(),
            session: HTTPTestSupport.session(for: PreferencesURLProtocol.self))

        let preferences = try await api.fetchPreferences()

        XCTAssertEqual(preferences.routing?[.critical], [.api])
        XCTAssertNil(preferences.quietHours)
    }

    func testUpdatePreferencesUsesAuthorizedBossEndpoint() async throws {
        PreferencesURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.path, "/api/boss/me/preferences")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            let body = try HTTPTestSupport.bodyData(from: request)
            let preferences = try JSONDecoder().decode(BossPreferences.self, from: body)
            XCTAssertEqual(preferences.routing?[.high], [.telegram])
            return try HTTPTestSupport.response(
                for: request,
                json: #"{"routing":{"critical":["api"],"high":["telegram"]}}"#
            )
        }
        let api = HibossAPI(config: try config(),
            session: HTTPTestSupport.session(for: PreferencesURLProtocol.self))

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


}

private final class PreferencesURLProtocol: HTTPTestProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: HibossAPIError.invalidResponse)
            return
        }
        complete { try handler(request) }
    }
}
