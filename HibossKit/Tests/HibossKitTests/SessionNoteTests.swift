// Verifies note wire decoding and authenticated list/create request contracts.
// Exports SessionNoteTests with isolated URLProtocol transport.
// Dependencies: XCTest, HTTPTestSupport and HibossKit.

import Foundation
import XCTest
@testable import HibossKit

final class SessionNoteTests: XCTestCase {
    private static let json = """
    {"id":"n1","session_id":"sess-exact","agent_id":"a1","boss_name":"Alex",
     "body":"Check the release","status":"pending","created_at":"2026-11-02 10:00:00","read_at":null}
    """

    override func tearDown() {
        NoteURLProtocol.handler = nil
        super.tearDown()
    }

    func testDecodesPendingAndReadTimestamps() throws {
        let pending = try JSONDecoder().decode(SessionNote.self, from: Data(Self.json.utf8))
        XCTAssertEqual(pending.status, .pending)
        XCTAssertNil(pending.readAt)
        XCTAssertEqual(pending.sessionID, "sess-exact")
        XCTAssertEqual(pending.agentID, "a1")
        XCTAssertEqual(pending.bossName, "Alex")
        XCTAssertNotNil(ISODate.parse(pending.createdAt))
        let readJSON = Self.json.replacingOccurrences(of: "\"pending\"", with: "\"read\"")
            .replacingOccurrences(of: "null", with: "\"2026-11-02 10:05:00\"")
        let read = try JSONDecoder().decode(SessionNote.self, from: Data(readJSON.utf8))
        XCTAssertEqual(read.status, .read)
        XCTAssertNotNil(ISODate.parse(read.readAt))
    }

    func testListUsesExactSessionPathAndEnvelope() async throws {
        NoteURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/boss/sessions/sess-exact/notes")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertNil(request.httpBody)
            return try Self.response(request, json: "{\"notes\":[\(Self.json)]}")
        }
        let notes = try await api().listSessionNotes(sessionID: "sess-exact")
        XCTAssertEqual(notes.map(\.id), ["n1"])
    }

    func testCreatePreservesBodyAndRetryKey() async throws {
        NoteURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/boss/sessions/sess-exact/notes")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "retry-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let data = try HTTPTestSupport.bodyData(from: request)
            XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: data),
                           ["body": "Check the release"])
            return try Self.response(request, json: Self.json, status: 201)
        }
        let client = try api()
        for _ in 0..<2 {
            let note = try await client.createSessionNote(
                sessionID: "sess-exact", body: "Check the release", idempotencyKey: "retry-key")
            XCTAssertEqual(note.id, "n1")
        }
    }

    func testViewerCannotCompose() async throws {
        NoteURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/boss/me")
            return try Self.response(request, json: "{\"role\":\"viewer\"}")
        }
        let allowed = try await api().canCreateSessionNotes()
        XCTAssertFalse(allowed)
    }

    private func api() throws -> HibossAPI {
        HibossAPI(config: ConnectionConfig(
            serverURL: try XCTUnwrap(URL(string: "https://hiboss.example")), bossToken: "test-token"),
            session: HTTPTestSupport.session(for: NoteURLProtocol.self))
    }

    private static func response(
        _ request: URLRequest, json: String, status: Int = 200
    ) throws -> (HTTPURLResponse, Data) {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: XCTUnwrap(request.url), statusCode: status, httpVersion: nil, headerFields: nil))
        return (response, Data(json.utf8))
    }
}

private final class NoteURLProtocol: HTTPTestProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: HibossAPIError.invalidResponse)
            return
        }
        complete { try handler(request) }
    }
}
