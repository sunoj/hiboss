// Integration coverage for the authenticated device-pairing endpoint.
// Exports: PairingAPITests for request shape, decoding, and credential-safe failures.
// Dependencies: XCTest, Foundation URLProtocol, and the HibossKit API client.

import Foundation
import XCTest
@testable import HibossKit

final class PairingAPITests: XCTestCase {
    override func tearDown() {
        PairingURLProtocol.handler = nil
        super.tearDown()
    }

    func testRequestPairingCodeUsesAuthorizedPostAndDecodesContract() async throws {
        let code = Self.validCode
        PairingURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/boss/pairing")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertNil(request.httpBody)
            return try HTTPTestSupport.response(
                for: request,
                json: "{\"code\":\"\(code)\",\"expires_at\":\"2026-09-03T10:05:00Z\"}"
            )
        }

        let grant = try await HibossAPI(config: Self.config,
            session: HTTPTestSupport.session(for: PairingURLProtocol.self)).requestPairingCode()

        XCTAssertEqual(grant.code, code)
        XCTAssertEqual(grant.expiresAt, try Date("2026-09-03T10:05:00Z", strategy: .iso8601))
    }

    func testPairingCodeValidationRequiresTheServerContractShape() {
        XCTAssertTrue(PairingGrant.isValidCode(Self.validCode))
        XCTAssertFalse(PairingGrant.isValidCode("hb_pair_not-a-code"))
        XCTAssertFalse(PairingGrant.isValidCode("hb_pair_" + String(repeating: "a", count: 63)))
    }

    func testPairingStatusUsesAuthorizedPostAndDecodesPairedDevice() async throws {
        PairingURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/boss/pairing/status")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            let body = try JSONDecoder().decode(
                PairingStatusRequestCapture.self,
                from: try HTTPTestSupport.bodyData(from: request)
            )
            XCTAssertEqual(body.code, Self.validCode)
            return try HTTPTestSupport.response(
                for: request,
                json: "{\"status\":\"paired\",\"device_label\":\"Ming’s iPhone\"}"
            )
        }

        let status = try await HibossAPI(config: Self.config,
            session: HTTPTestSupport.session(for: PairingURLProtocol.self))
            .pairingStatus(code: Self.validCode)

        XCTAssertEqual(status, .paired(deviceLabel: "Ming’s iPhone"))
    }

    func testPairingStatusDecodesPendingAndExpiredStates() async throws {
        for (wireStatus, expected) in [
            ("pending", PairingStatus.pending),
            ("expired", PairingStatus.expired),
        ] {
            PairingURLProtocol.handler = { request in
                try HTTPTestSupport.response(for: request, json: "{\"status\":\"" + wireStatus + "\"}")
            }
            let status = try await HibossAPI(config: Self.config,
                session: HTTPTestSupport.session(for: PairingURLProtocol.self))
                .pairingStatus(code: Self.validCode)
            XCTAssertEqual(status, expected)
        }
    }

    func testMalformedPairingResponseDoesNotEchoCredentialInError() async throws {
        let invalidCode = "hb_pair_not-a-code"
        PairingURLProtocol.handler = { request in
            try HTTPTestSupport.response(
                for: request,
                json: "{\"code\":\"\(invalidCode)\",\"expires_at\":\"2026-09-03T10:05:00Z\"}"
            )
        }

        do {
            _ = try await HibossAPI(config: Self.config,
                session: HTTPTestSupport.session(for: PairingURLProtocol.self)).requestPairingCode()
            XCTFail("Expected malformed pairing response to fail")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains(invalidCode))
        }
    }

    private static let validCode = "hb_pair_" + String(repeating: "a", count: 64)
    private static let config = ConnectionConfig(
        serverURL: URL(string: "https://hiboss.example")!,
        bossToken: "test-token"
    )


}

private struct PairingStatusRequestCapture: Decodable {
    let code: String
}

private final class PairingURLProtocol: HTTPTestProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: HibossAPIError.invalidResponse)
            return
        }
        complete { try handler(request) }
    }
}
