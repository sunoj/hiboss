// Verifies pending questionnaire wire pagination and failure handling with local stubs.
// Exports API unit tests; all HTTP requests are intercepted by URLProtocol.
// Dependencies: XCTest, Foundation, and HibossAPI; no live server or UI execution.

import Foundation
import XCTest
@testable import HibossKit

final class QuestionnaireAPITests: XCTestCase {
    override func tearDown() { QuestionnaireURLProtocol.handler = nil; super.tearDown() }

    func testLoadsAllPagesAndEncodesTheOpaqueCursor() async throws {
        QuestionnaireURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/interaction-requests")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-token")
            let cursor = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
            let id = cursor == nil ? "first" : "second"
            if let cursor { XCTAssertEqual(cursor, "opaque/+?=") }
            let next: PanelValue = cursor == nil ? .string("opaque/+?=") : .null
            let page: PanelValue = .object(["requests": .array([.object([
                "requestId": .string(id), "panelId": .string("panel"), "requestRevision": .number(2), "title": .string("Settings"),
                "blocking": .bool(false), "expiresAt": .null, "createdAt": .string("2026-09-11T00:00:00Z")])]), "nextCursor": next])
            return (200, try JSONEncoder().encode(page))
        }
        let records = try await api().fetchPendingQuestionnaires()
        XCTAssertEqual(records.map(\.id), ["first", "second"])
        XCTAssertFalse(records[0].blocking)
        XCTAssertEqual(records[0].requestRevision, 2)
    }

    func testRejectsRepeatedCursorsInsteadOfLoopingForever() async throws {
        QuestionnaireURLProtocol.handler = { _ in (200, Data(#"{"requests":[],"nextCursor":"repeated"}"#.utf8)) }
        do { _ = try await api().fetchPendingQuestionnaires(); XCTFail("Expected invalid pagination") }
        catch { XCTAssertTrue(error is HibossAPIError) }
    }

    func testDoesNotTreatAuthenticationFailureAsAnEmptyInbox() async throws {
        QuestionnaireURLProtocol.handler = { _ in (401, Data(#"{"error":"Unauthorized"}"#.utf8)) }
        do { _ = try await api().fetchPendingQuestionnaires(); XCTFail("Expected authentication failure") }
        catch { XCTAssertEqual((error as? HibossAPIError)?.isAuthFailure, true) }
    }

    private func api() -> HibossAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [QuestionnaireURLProtocol.self]
        return HibossAPI(config: ConnectionConfig(serverURL: URL(string: "https://unit.test")!, bossToken: "unit-token"), session: URLSession(configuration: config))
    }
}

private final class QuestionnaireURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw HibossAPIError.invalidResponse }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
