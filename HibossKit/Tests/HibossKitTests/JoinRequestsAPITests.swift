// Tests join-request decoding and the list/approve/reject routes with typed error mapping.
// Exports: JoinRequestsAPITests; HTTP traffic uses an in-memory URLProtocol.
// Dependencies: XCTest, Foundation, and HibossKit.

import Foundation
import XCTest
@testable import HibossKit

final class JoinRequestsAPITests: XCTestCase {
    static let fullJSON = #"{"id":"jr-1","status":"pending","device_label":"mini","device_host":"mini.local","device_id":"dev-9","inviter_label":"Office Mac","verification_code":"012345","profiles":[{"profile":"claude","name":"mini-claude"},{"profile":"codex","name":"mini-codex"}],"created_at":"2026-10-03 08:00:00","updated_at":"2026-10-03 08:00:00"}"#
    static let sparseJSON = #"{"id":"jr-2","status":"pending","device_label":"lab","device_host":null,"device_id":null,"inviter_label":null,"verification_code":null,"profiles":[],"created_at":"2026-10-03T08:00:00.000Z","updated_at":"2026-10-03T08:00:00.000Z"}"#

    override func tearDown() {
        JoinURLProtocol.handler = nil
        super.tearDown()
    }

    func testDecodesFullAndNullFields() throws {
        let full = try JSONDecoder().decode(JoinRequest.self, from: Data(Self.fullJSON.utf8))
        XCTAssertEqual(full.deviceHost, "mini.local")
        XCTAssertEqual(full.inviterLabel, "Office Mac")
        XCTAssertEqual(full.displayCode, "012345", "leading zero must survive")
        XCTAssertTrue(full.canApprove)
        XCTAssertEqual(full.profiles.map(\.name), ["mini-claude", "mini-codex"])
        XCTAssertEqual(full.createdDate, try Date("2026-10-03T08:00:00Z", strategy: .iso8601))

        let sparse = try JSONDecoder().decode(JoinRequest.self, from: Data(Self.sparseJSON.utf8))
        XCTAssertNil(sparse.deviceHost)
        XCTAssertNil(sparse.deviceID)
        XCTAssertNil(sparse.inviterLabel)
        XCTAssertNil(sparse.displayCode)
        XCTAssertFalse(sparse.canApprove, "no code on screen means no approval")
        XCTAssertNotNil(sparse.createdDate)
    }

    func testBlankCodeCannotBeApproved() {
        XCTAssertFalse(JoinRequest(id: "x", deviceLabel: "x", verificationCode: "  ").canApprove)
    }

    func testListRequestsPendingWithBearer() async throws {
        JoinURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/base/api/boss/join-requests")
            XCTAssertEqual(request.url?.query, "status=pending")
            return (200, "{\"requests\":[\(Self.fullJSON),\(Self.sparseJSON)]}")
        }
        let requests = try await api().listPendingJoinRequests()
        XCTAssertEqual(requests.map(\.id), ["jr-1", "jr-2"])
    }

    func testApprovePostsAndDecodesAgents() async throws {
        JoinURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/base/api/boss/join-requests/jr-1/approve")
            return (200, #"{"id":"jr-1","status":"approved","device_id":"dev-9","agents":[{"profile":"claude","name":"mini-claude","agent_id":"a-1"}]}"#)
        }
        let approval = try await api().approveJoinRequest(id: "jr-1")
        XCTAssertEqual(approval.status, "approved")
        XCTAssertEqual(approval.deviceID, "dev-9")
        XCTAssertEqual(approval.agents.map(\.agentID), ["a-1"])
    }

    func testRejectPosts() async throws {
        JoinURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/base/api/boss/join-requests/jr-1/reject")
            return (200, #"{"id":"jr-1","status":"rejected"}"#)
        }
        try await api().rejectJoinRequest(id: "jr-1")
    }

    func testStatusCodesMapToTypedErrors() async throws {
        let cases: [(Int, String, JoinRequestError)] = [
            (403, "admin role required", .forbidden),
            (404, "not found", .notFound),
            (409, "  name mini-claude is taken \n", .conflict("name mini-claude is taken")),
        ]
        for (status, body, expected) in cases {
            JoinURLProtocol.handler = { _ in (status, body) }
            let service = try api()
            await XCTAssertThrowsJoinError(expected) { _ = try await service.listPendingJoinRequests() }
            await XCTAssertThrowsJoinError(expected) { _ = try await service.approveJoinRequest(id: "jr-1") }
            await XCTAssertThrowsJoinError(expected) { try await service.rejectJoinRequest(id: "jr-1") }
        }
        XCTAssertEqual(JoinRequestError.forbidden.errorDescription, kitL("Only an admin can approve devices"))
        XCTAssertEqual(JoinRequestError.conflict("").errorDescription, kitL("This request was already processed."))
    }

    func testOtherFailuresStayGenericAPIErrors() async throws {
        JoinURLProtocol.handler = { _ in (401, "") }
        do {
            _ = try await api().listPendingJoinRequests()
            XCTFail("Expected failure")
        } catch let error as HibossAPIError {
            XCTAssertTrue(error.isAuthFailure)
        }
    }

    private func XCTAssertThrowsJoinError(
        _ expected: JoinRequestError, _ body: () async throws -> Void, line: UInt = #line
    ) async {
        do {
            try await body()
            XCTFail("Expected \(expected)", line: line)
        } catch {
            XCTAssertEqual(error as? JoinRequestError, expected, line: line)
        }
    }

    private func api() throws -> HibossAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [JoinURLProtocol.self]
        let session = URLSession(configuration: configuration)
        addTeardownBlock { session.invalidateAndCancel() }
        return HibossAPI(config: ConnectionConfig(
            serverURL: try XCTUnwrap(URL(string: "https://hiboss.example/base")), bossToken: "boss-token"
        ), session: session)
    }
}

private final class JoinURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer boss-token")
            let handler = try XCTUnwrap(Self.handler)
            let (status, body) = try handler(request)
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url), statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": status < 300 ? "application/json" : "text/plain"]
            ))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}
