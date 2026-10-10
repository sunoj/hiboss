// Covers the session facts the boss session inventory returns (host, start, status).
// A malformed or missing fact must never drop the session from the list.

import XCTest
@testable import HibossKit

final class ProjectSessionFactsTests: XCTestCase {
    private func session(_ json: String) throws -> ProjectSession {
        try JSONDecoder().decode(ProjectSession.self, from: Data(json.utf8))
    }

    func testDecodesInventoryFacts() throws {
        let decoded = try session("""
        {"id":"s1","project_slug":"house","branch":"main","label":"house/main",
         "host":"Mac mini","agent_name":"claude","status":"working",
         "status_text":"Pricing the garage slab","started_at":"2026-10-09 02:12:00",
         "last_seen_at":"2026-10-09 07:44:00"}
        """)
        XCTAssertEqual(decoded.host, "Mac mini")
        XCTAssertEqual(decoded.agentName, "claude")
        XCTAssertEqual(decoded.status, "working")
        XCTAssertEqual(decoded.statusText, "Pricing the garage slab")
        XCTAssertEqual(decoded.startedAt, "2026-10-09 02:12:00")
        XCTAssertEqual(decoded.lastSeenAt, "2026-10-09 07:44:00")
    }

    func testOlderServerWithoutFactsStillDecodes() throws {
        let decoded = try session(#"{"id":"s1","project_slug":"house","branch":"main"}"#)
        XCTAssertNil(decoded.host)
        XCTAssertNil(decoded.startedAt)
        XCTAssertEqual(decoded.displayLabel, "house/main")
    }

    func testMalformedFactDoesNotDropTheSession() throws {
        let decoded = try session(#"{"id":"s1","host":42,"status":["x"],"started_at":null}"#)
        XCTAssertEqual(decoded.id, "s1")
        XCTAssertNil(decoded.host)
        XCTAssertNil(decoded.status)
        XCTAssertNil(decoded.startedAt)
    }

    func testRoundTrip() throws {
        let original = try session(#"{"id":"s1","host":"Air","status":"idle"}"#)
        let again = try JSONDecoder().decode(ProjectSession.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(again, original)
    }
}

final class ProjectIdentityAvatarTests: XCTestCase {
    private func session(_ json: String) throws -> ProjectSession {
        try JSONDecoder().decode(ProjectSession.self, from: Data(json.utf8))
    }

    func testNicknameAndAvatarDecode() throws {
        let decoded = try session("""
        {"id":"s1","nickname":"otter","project_ref":{"id":"p","slug":"smart-router",
         "display_name":"Smart Router","avatar_url":"https://hiboss.example/a.png"}}
        """)
        XCTAssertEqual(decoded.nickname, "otter")
        XCTAssertEqual(decoded.projectRef?.avatarURL?.absoluteString, "https://hiboss.example/a.png")
        XCTAssertEqual(decoded.projectRef?.placeholder.initial, "S")
    }

    func testMissingOrUnsafeAvatarFallsBackToPlaceholder() throws {
        for raw in ["null", "\"file:///etc/passwd\"", "42", "\"not a url\""] {
            let decoded = try session(#"{"id":"s1","project_ref":{"id":"p","slug":"x","display_name":"X","avatar_url":\#(raw)}}"#)
            XCTAssertNil(decoded.projectRef?.avatarURL, raw)
            XCTAssertNotNil(decoded.projectRef)
        }
        XCTAssertNil(try session(#"{"id":"s1"}"#).nickname)
    }
}

final class ProjectSessionHeartbeatTests: XCTestCase {
    func testServerHeartbeatFormatsParseAsUTC() throws {
        let plain = try JSONDecoder().decode(ProjectSession.self,
            from: Data(#"{"id":"a","last_seen_at":"2026-10-10 07:00:00"}"#.utf8))
        let iso = try JSONDecoder().decode(ProjectSession.self,
            from: Data(#"{"id":"b","last_seen_at":"2026-10-10T07:00:00Z"}"#.utf8))
        XCTAssertEqual(plain.lastSeenDate, iso.lastSeenDate)
        XCTAssertNotNil(plain.lastSeenDate)
        XCTAssertEqual(ProjectSession.heartbeats([plain, iso]).count, 2)
        XCTAssertNil(ProjectSession(id: "c", projectId: nil, projectSlug: nil, branch: nil).lastSeenDate)
    }
}
