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
            return try Self.response(
                for: request,
                json: "{\"code\":\"\(code)\",\"expires_at\":\"2026-09-03T10:05:00Z\"}"
            )
        }

        let grant = try await HibossAPI(config: Self.config, session: Self.session()).requestPairingCode()

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
                from: try Self.bodyData(from: request)
            )
            XCTAssertEqual(body.code, Self.validCode)
            return try Self.response(
                for: request,
                json: "{\"status\":\"paired\",\"device_label\":\"Ming’s iPhone\"}"
            )
        }

        let status = try await HibossAPI(config: Self.config, session: Self.session())
            .pairingStatus(code: Self.validCode)

        XCTAssertEqual(status, .paired(deviceLabel: "Ming’s iPhone"))
    }

    func testPairingStatusDecodesPendingAndExpiredStates() async throws {
        for (wireStatus, expected) in [
            ("pending", PairingStatus.pending),
            ("expired", PairingStatus.expired),
        ] {
            PairingURLProtocol.handler = { request in
                try Self.response(for: request, json: "{\"status\":\"" + wireStatus + "\"}")
            }
            let status = try await HibossAPI(config: Self.config, session: Self.session())
                .pairingStatus(code: Self.validCode)
            XCTAssertEqual(status, expected)
        }
    }

    func testMalformedPairingResponseDoesNotEchoCredentialInError() async throws {
        let invalidCode = "hb_pair_not-a-code"
        PairingURLProtocol.handler = { request in
            try Self.response(
                for: request,
                json: "{\"code\":\"\(invalidCode)\",\"expires_at\":\"2026-09-03T10:05:00Z\"}"
            )
        }

        do {
            _ = try await HibossAPI(config: Self.config, session: Self.session()).requestPairingCode()
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

    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PairingURLProtocol.self]
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
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? HibossAPIError.invalidResponse }
            if count == 0 { return data }
            data.append(buffer, count: count)
        }
    }
}

private struct PairingStatusRequestCapture: Decodable {
    let code: String
}

private final class PairingURLProtocol: URLProtocol, @unchecked Sendable {
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
