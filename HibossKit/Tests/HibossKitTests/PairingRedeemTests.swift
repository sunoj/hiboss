// Integration coverage for the unauthenticated pairing redemption request and its failures.
// Exports: PairingRedeemTests for request shape, signing passthrough, and status mapping.
// Dependencies: XCTest, Foundation URLProtocol, and HibossKit's PairingRedeemClient.

import Foundation
import XCTest
@testable import HibossKit

final class PairingRedeemTests: XCTestCase {
    override func tearDown() {
        RedeemURLProtocol.handler = nil
        super.tearDown()
    }

    func testRedeemPostsCodeAndDeviceLabelWithoutAuthorization() async throws {
        RedeemURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://hiboss.example/team/api/pairing/redeem")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: try requestBody(request)) as? [String: String]
            )
            XCTAssertEqual(body, ["code": Self.code, "device_label": "Ming’s MacBook"])
            return (200, #"{"token":"hb_boss_secret","boss":{"id":"boss-1","name":"Ming","role":"admin"}}"#)
        }

        let grant = try await Self.client().redeem(
            payload: try Self.payload(), deviceLabel: "Ming’s MacBook"
        )

        XCTAssertEqual(grant.token, "hb_boss_secret")
        XCTAssertEqual(grant.bossID, "boss-1")
        XCTAssertNil(grant.signingKeyID)
    }

    func testRedeemRequestIncludesSigningRegistrationWhenProvided() throws {
        let registration = PairingSigningRegistration(
            algorithm: "ES256", clientKind: .ios, publicKey: "public-key", proof: "pairing-proof"
        )
        let request = PairingRedeemRequest(code: Self.code, deviceLabel: "Ming’s iPhone", signing: registration)

        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        let signing = try XCTUnwrap(encoded?["signing"] as? [String: String])

        XCTAssertEqual(encoded?["device_label"] as? String, "Ming’s iPhone")
        XCTAssertEqual(signing["algorithm"], "ES256")
        XCTAssertEqual(signing["client_kind"], "ios")
        XCTAssertEqual(signing["public_key"], "public-key")
        XCTAssertEqual(signing["proof"], "pairing-proof")
    }

    func testRedeemMapsServerRejectionsWithoutEchoingTheCode() async throws {
        for (status, expected) in [(400, PairingRedeemError.invalidOrExpired), (500, .requestFailed)] {
            RedeemURLProtocol.handler = { _ in (status, "invalid or expired pairing code") }
            do {
                _ = try await Self.client().redeem(payload: try Self.payload(), deviceLabel: "Mac")
                XCTFail("Expected HTTP \(status) to fail")
            } catch {
                XCTAssertEqual(error as? PairingRedeemError, expected)
                XCTAssertFalse(error.localizedDescription.contains(Self.code))
            }
        }
    }

    func testRedeemRejectsAResponseWithoutAToken() async throws {
        RedeemURLProtocol.handler = { _ in (200, #"{"token":"","boss":{"id":"boss-1"}}"#) }
        do {
            _ = try await Self.client().redeem(payload: try Self.payload(), deviceLabel: "Mac")
            XCTFail("Expected an empty token to fail")
        } catch {
            XCTAssertEqual(error as? PairingRedeemError, .invalidResponse)
        }
    }

    func testDeviceLabelFitsTheServerContract() {
        XCTAssertEqual(
            DeviceLabel.sanitize("Ming’s iPhone <office>\u{0000} & backup", fallback: "iPhone"),
            "Ming’s iPhone office backup"
        )
        XCTAssertEqual(DeviceLabel.sanitize(String(repeating: "x", count: 101), fallback: "Mac").count, 100)
        XCTAssertEqual(DeviceLabel.sanitize(" \n ", fallback: "Mac"), "Mac")
    }

    private static let code = "hb_pair_" + String(repeating: "b", count: 64)

    private static func payload() throws -> PairingPayload {
        try PairingPayload.make(server: "https://hiboss.example/team", code: code).get()
    }

    private static func client() -> PairingRedeemClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedeemURLProtocol.self]
        return PairingRedeemClient(session: URLSession(configuration: configuration))
    }
}

private func requestBody(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody { return body }
    let stream = try XCTUnwrap(request.httpBodyStream)
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while case let count = stream.read(&buffer, maxLength: buffer.count), count > 0 {
        data.append(buffer, count: count)
    }
    return data
}

private final class RedeemURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, String))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (status, body) = try handler(request)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
            client?.urlProtocol(self, didReceive: response ?? HTTPURLResponse(), cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
