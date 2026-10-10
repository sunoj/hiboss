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
