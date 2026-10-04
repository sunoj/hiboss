// Coverage for "Sign in with iPhone" in HibossKit: link parsing, the Mac's unauthenticated
// open/status/complete requests, and the boss's review/approve/reject calls.
// Dependencies: XCTest, Foundation URLProtocol, and HibossKit's Signin types.

import Foundation
import XCTest
@testable import HibossKit

final class SigninTests: XCTestCase {
    private static let requestID = String(repeating: "a1", count: 16)
    private static let server = URL(string: "https://hiboss.example/team")!

    override func tearDown() {
        SigninURLProtocol.handler = nil
        super.tearDown()
    }

    func testLinkRoundTripsAndRefusesOtherShapes() throws {
        let link = try XCTUnwrap(SigninLink(serverURL: Self.server, requestID: Self.requestID))
        let url = try XCTUnwrap(link.url)
        XCTAssertEqual(try SigninLink.parse(url.absoluteString).get(), link)
        XCTAssertEqual(SigninLink.parse("hiboss://pair?server=https://a&code=x"), .failure(.notASigninLink))
        XCTAssertEqual(SigninLink.parse("hiboss://signin?server=http://evil.example&request=\(Self.requestID)"), .failure(.insecureServer))
        XCTAssertEqual(SigninLink.parse("hiboss://signin?server=https://a.example&request=ABC"), .failure(.malformed))
        XCTAssertNotNil(SigninLink(serverURL: URL(string: "http://127.0.0.1:8787")!, requestID: Self.requestID))
    }

    func testOpenPostsLabelWithoutAuthorizationAndReturnsTicket() async throws {
        SigninURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://hiboss.example/team/api/signin/requests")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(try Self.json(request), ["device_label": "Studio Mac"])
            return (201, #"{"request_id":"\#(Self.requestID)","poll_token":"st_abc","expires_at":"2026-10-04T12:00:00.000Z"}"#)
        }
        let ticket = try await Self.client().open(server: Self.server, deviceLabel: "Studio Mac")
        XCTAssertEqual(ticket.link.requestID, Self.requestID)
        XCTAssertEqual(ticket.pollToken, "st_abc")
    }

    func testStatusAndCompleteSendThePollTokenHeader() async throws {
        let ticket = try Self.ticket()
        SigninURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Signin-Token"), "st_abc")
            if request.url?.lastPathComponent == "status" { return (200, #"{"status":"approved","expires_at":"x"}"#) }
            XCTAssertEqual(try Self.json(request), ["code": "123456"])
            return (200, #"{"token":"hb_boss_new","boss":{"id":"boss-1","name":"Ming","role":"admin"}}"#)
        }
        let progress = try await Self.client().status(ticket)
        XCTAssertEqual(progress, .approved)
        let grant = try await Self.client().complete(ticket, code: "123456", signing: nil)
        XCTAssertEqual(grant.token, "hb_boss_new")
        XCTAssertEqual(grant.bossID, "boss-1")
    }

    func testCompleteMapsAWrongCodeAndTheCap() async throws {
        let ticket = try Self.ticket()
        SigninURLProtocol.handler = { _ in (400, "incorrect code or request no longer valid") }
        await XCTAssertThrowsAsync(try await Self.client().complete(ticket, code: "000000", signing: nil), .incorrectCodeOrInvalid)
        SigninURLProtocol.handler = { _ in (429, "too many open sign-in requests") }
        await XCTAssertThrowsAsync(try await Self.client().open(server: Self.server, deviceLabel: "Mac"), .tooManyRequests)
    }

    func testBossApprovesAndReceivesTheCode() async throws {
        SigninURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/team/api/boss/signin-requests/\(Self.requestID)/approve")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer hb_boss_phone")
            return (200, #"{"code":"042517","expires_at":"2026-10-04T12:00:00.000Z","device_label":"Studio Mac"}"#)
        }
        let approval = try await Self.api().approveSignin(id: Self.requestID)
        XCTAssertEqual(approval.code, "042517")
        XCTAssertEqual(approval.deviceLabel, "Studio Mac")
    }

    func testBossReviewDecodesTheRequest() async throws {
        SigninURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            return (200, #"{"request_id":"\#(Self.requestID)","device_label":"Studio Mac","origin":"JP · Tokyo","status":"pending","created_at":"x","expires_at":"y"}"#)
        }
        let summary = try await Self.api().signinRequest(id: Self.requestID)
        XCTAssertEqual(summary.origin, "JP · Tokyo")
        XCTAssertEqual(summary.status, .pending)
    }

    private static func ticket() throws -> SigninTicket {
        let link = try XCTUnwrap(SigninLink(serverURL: server, requestID: requestID))
        return SigninTicket(link: link, pollToken: "st_abc", expiresAt: Date())
    }

    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SigninURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func client() -> SigninClient { SigninClient(session: session()) }

    private static func api() -> HibossAPI {
        HibossAPI(config: ConnectionConfig(serverURL: server, bossToken: "hb_boss_phone"), session: session())
    }

    private static func json(_ request: URLRequest) throws -> [String: String] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while case let count = stream.read(&buffer, maxLength: buffer.count), count > 0 { data.append(buffer, count: count) }
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
    }
}

private func XCTAssertThrowsAsync<T>(
    _ expression: @autoclosure () async throws -> T, _ expected: SigninError, file: StaticString = #filePath, line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("expected \(expected)", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? SigninError, expected, file: file, line: line)
    }
}

private final class SigninURLProtocol: URLProtocol, @unchecked Sendable {
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
