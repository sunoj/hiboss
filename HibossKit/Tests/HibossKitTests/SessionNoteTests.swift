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
        XCTAssertEqual(pending.images, [])
        XCTAssertEqual(pending.replies, [])
        let emptyJSON = Self.json.replacingOccurrences(
            of: "\"read_at\":null", with: "\"images\":[],\"read_at\":null")
        XCTAssertEqual(try JSONDecoder().decode(SessionNote.self, from: Data(emptyJSON.utf8)).images, [])
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

    func testDecodesRepliesAndPreservesWireOrder() throws {
        let replies = """
        "replies":[{"message_id":"m1","body":"Checked","agent_name":"worker",
        "created_at":"2026-11-02 10:01:00"},{"message_id":"m2","body":"Ready",
        "agent_name":"worker","created_at":"2026-11-02 10:02:00"}],
        """
        let json = Self.json.replacingOccurrences(of: "\"read_at\":null", with: replies + "\"read_at\":null")
        let note = try JSONDecoder().decode(SessionNote.self, from: Data(json.utf8))
        XCTAssertEqual(note.replies.map(\.messageID), ["m1", "m2"])
        XCTAssertEqual(note.replies.map(\.body), ["Checked", "Ready"])
        XCTAssertEqual(note.replies.first?.agentName, "worker")
        XCTAssertNotNil(ISODate.parse(note.replies.first?.createdAt))
        let encoded = try JSONEncoder().encode(note)
        XCTAssertEqual(try JSONDecoder().decode(SessionNote.self, from: encoded), note)
        let empty = Self.json.replacingOccurrences(of: "\"read_at\":null",
                                                  with: "\"replies\":[],\"read_at\":null")
        XCTAssertEqual(try JSONDecoder().decode(SessionNote.self, from: Data(empty.utf8)).replies, [])
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
            let type = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
            XCTAssertTrue(type.hasPrefix("multipart/form-data; boundary="))
            let boundary = String(type.dropFirst("multipart/form-data; boundary=".count))
            let data = try HTTPTestSupport.bodyData(from: request)
            XCTAssertEqual(String(decoding: data, as: UTF8.self),
                "--\(boundary)\r\nContent-Disposition: form-data; name=\"body\"\r\n\r\n"
                + "Check the release\r\n--\(boundary)--\r\n")
            return try Self.response(request, json: Self.json, status: 201)
        }
        let client = try api()
        for _ in 0..<2 {
            let note = try await client.createSessionNote(
                sessionID: "sess-exact", body: "Check the release", images: [], idempotencyKey: "retry-key")
            XCTAssertEqual(note.id, "n1")
        }
    }

    func testImageMetadataAndMultipartFiles() async throws {
        let json = Self.json.trimmingCharacters(in: .whitespacesAndNewlines).dropLast()
            + " ,\"images\":[{\"index\":0,"
            + "\"content_type\":\"image/jpeg\",\"bytes\":3}]}"
        let decoded = try JSONDecoder().decode(SessionNote.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.images, [SessionNoteImage(index: 0, contentType: "image/jpeg", bytes: 3)])
        NoteURLProtocol.handler = { request in
            let data = try HTTPTestSupport.bodyData(from: request)
            let text = String(decoding: data, as: UTF8.self)
            XCTAssertTrue(text.contains("name=\"body\"\r\n\r\n\r\n--"))
            XCTAssertTrue(text.contains("name=\"image\"; filename=\"0.jpg\"\r\nContent-Type: image/jpeg"))
            XCTAssertTrue(text.contains("\r\n\r\nabc\r\n--"))
            XCTAssertTrue(text.contains("name=\"image\"; filename=\"1.gif\"\r\nContent-Type: image/gif"))
            XCTAssertTrue(text.contains("\r\n\r\nGIF89a\r\n--"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "image-retry")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            return try Self.response(request, json: Self.json)
        }
        _ = try await api().createSessionNote(sessionID: "sess-exact", body: "",
            images: [SessionNoteUpload(data: Data("abc".utf8), contentType: "image/jpeg"),
                     SessionNoteUpload(data: Data("GIF89a".utf8), contentType: "image/gif")],
            idempotencyKey: "image-retry")
    }

    func testImageFetchUsesAuthenticatedNoteRoute() async throws {
        NoteURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/boss/sessions/sess-exact/notes/n1/images/0")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            return try Self.response(request, json: "image bytes")
        }
        let bytes = try await api().sessionNoteImage(sessionID: "sess-exact", noteID: "n1", index: 0)
        XCTAssertEqual(bytes, Data("image bytes".utf8))
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
