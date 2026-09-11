// Tests client decoding, authenticated calls, and credential-safe failures.
// Exports: BossClientsAPITests; all HTTP traffic uses an in-memory URLProtocol.
// Dependencies: XCTest, Foundation, and HibossKit.

import Foundation
import XCTest
@testable import HibossKit

final class BossClientsAPITests: XCTestCase {
    static let clientJSON = #"{"id":"client-1","kind":"macos","label":"Office Mac","created_at":"2026-09-11 10:00:00","last_seen_at":null,"revoked_at":null,"has_push_device":false,"has_signing_key":true,"is_current":false}"#

    override func tearDown() {
        ClientsURLProtocol.handler = nil
        super.tearDown()
    }

    func testCreateUsesAuthorizedPostAndReturnsFreshCredential() async throws {
        ClientsURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try JSONDecoder().decode(Registration.self, from: Self.body(request))
            XCTAssertEqual(body.kind, "macos")
            XCTAssertEqual(body.label, "Office Mac")
            return (201, "{\"client\":\(Self.clientJSON),\"token\":\"fresh-token\"}")
        }
        let grant = try await api().createClient(kind: .macos, label: "Office Mac")
        XCTAssertEqual(grant.token, "fresh-token")
        XCTAssertEqual(grant.client.id.rawValue, "client-1")
        XCTAssertNil(grant.client.lastSeenAt)
        XCTAssertTrue(grant.client.hasSigningKey)
        XCTAssertFalse(grant.client.hasPushDevice)
    }

    func testListDecodesCurrentPushAndRevokedInventory() async throws {
        let current = Self.clientJSON.replacingOccurrences(of: "\"is_current\":false", with: "\"is_current\":true")
            .replacingOccurrences(of: "\"has_push_device\":false", with: "\"has_push_device\":true")
        let revoked = Self.clientJSON.replacingOccurrences(of: "\"revoked_at\":null", with: "\"revoked_at\":\"2026-09-11 11:00:00\"")
        ClientsURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            return (200, "{\"clients\":[\(current),\(revoked)]}")
        }
        let clients = try await api().listClients()
        XCTAssertEqual(clients.count, 2)
        XCTAssertTrue(clients[0].isCurrent)
        XCTAssertTrue(clients[0].hasPushDevice)
        XCTAssertFalse(clients[0].canRevoke)
        XCTAssertNotNil(clients[1].revokedAt)
        XCTAssertFalse(clients[1].canRevoke)
        XCTAssertTrue(clients[1].hasSigningKey)
    }

    func testLastSeenDecodesSQLiteAndISOTimeForAllKinds() throws {
        for kind in ["ios", "macos", "web", "cli"] {
            for timestamp in ["2026-09-11 10:00:00", "2026-09-11T10:00:00Z", "2026-09-11T10:00:00.000Z"] {
                let json = Self.clientJSON.replacingOccurrences(of: "macos", with: kind)
                    .replacingOccurrences(of: "\"last_seen_at\":null", with: "\"last_seen_at\":\"\(timestamp)\"")
                let client = try JSONDecoder().decode(BossClient.self, from: Data(json.utf8))
                XCTAssertEqual(client.kind.rawValue, kind)
                XCTAssertEqual(client.lastSeenDate, try Date("2026-09-11T10:00:00Z", strategy: .iso8601))
                XCTAssertTrue(client.canRevoke)
            }
        }
    }

    func testRevokeUsesAuthorizedDeleteAndAllowsEmptySuccessBody() async throws {
        ClientsURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.lastPathComponent, "client-1")
            XCTAssertNil(request.httpBody)
            return (204, "")
        }
        try await api().revokeClient(id: BossClientID(rawValue: "client-1"))
    }

    func testAllCallsSurfaceServerFailures() async throws {
        ClientsURLProtocol.handler = { _ in (403, "{}") }
        for operation in 0..<3 {
            do {
                let service = try api()
                switch operation {
                case 0: _ = try await service.createClient(kind: .ios, label: "Phone")
                case 1: _ = try await service.listClients()
                default: try await service.revokeClient(id: BossClientID(rawValue: "client-1"))
                }
                XCTFail("Expected rejected credentials")
            } catch let error as HibossAPIError {
                XCTAssertTrue(error.isAuthFailure)
            }
        }
    }

    func testMalformedGrantDoesNotExposeToken() async throws {
        ClientsURLProtocol.handler = { _ in (201, #"{"token":"secret-token","client":null}"#) }
        do {
            _ = try await api().createClient(kind: .ios, label: "Phone")
            XCTFail("Expected invalid grant")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains("secret-token"))
        }
    }

    func testEmptyGrantTokenIsRejected() async throws {
        ClientsURLProtocol.handler = { _ in (201, "{\"client\":\(Self.clientJSON),\"token\":\"\"}") }
        do {
            _ = try await api().createClient(kind: .ios, label: "Phone")
            XCTFail("Expected invalid grant")
        } catch let error as HibossAPIError {
            guard case .invalidResponse = error else { return XCTFail("Expected invalid response") }
        }
    }

    private func api() throws -> HibossAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ClientsURLProtocol.self]
        let session = URLSession(configuration: configuration)
        addTeardownBlock { session.invalidateAndCancel() }
        return HibossAPI(config: ConnectionConfig(
            serverURL: try XCTUnwrap(URL(string: "https://hiboss.example/base")), bossToken: "pasted-token"
        ), session: session)
    }

    private static func body(_ request: URLRequest) throws -> Data {
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

private struct Registration: Decodable {
    let kind: String
    let label: String
}

private final class ClientsURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer pasted-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let expectedPath = request.httpMethod == "DELETE" ? "/base/api/boss/clients/client-1" : "/base/api/boss/clients"
            XCTAssertEqual(request.url?.path, expectedPath)
            let handler = try XCTUnwrap(Self.handler)
            let (status, json) = try handler(request)
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url), statusCode: status, httpVersion: nil, headerFields: nil
            ))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}
