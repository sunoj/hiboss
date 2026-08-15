// Coverage for session event decoding and the session SSE line decoder.
// Exports: SessionEventDecodingTests.
// Dependencies: XCTest and HibossKit SessionEvent / SessionSSEDecoder.

import Foundation
import XCTest
@testable import HibossKit

final class SessionEventDecodingTests: XCTestCase {
    func testDecodesOpenKindAndNestedPayload() throws {
        let json = """
        {"id":"e1","session_id":"s1","sequence":7,"kind":"tool_call",
         "direction":"agent_to_boss","actor_name":"cli","message_id":"m1",
         "source":{"record_type":"assistant"},
         "payload":{"body":"running","tool":"bash","args":["ls"]},
         "raw":{"type":"assistant"},
         "created_at":"2026-08-14T09:00:00.123Z"}
        """
        let event = try JSONDecoder().decode(SessionEvent.self, from: Data(json.utf8))
        XCTAssertEqual(event.sequence, 7)
        XCTAssertEqual(event.kind, "tool_call")
        XCTAssertEqual(event.displayBody, "running")
        XCTAssertEqual(event.payload?.objectValue?["tool"]?.stringValue, "bash")
    }

    func testUnknownKindUsesCompactPayloadPreview() throws {
        let json = """
        {"id":"e9","session_id":"s1","sequence":9,"kind":"future_kind",
         "payload":{"note":"keep me","count":2},"created_at":"2026-08-14T09:00:00Z"}
        """
        let event = try JSONDecoder().decode(SessionEvent.self, from: Data(json.utf8))
        XCTAssertFalse(event.isKnownKind)
        XCTAssertEqual(event.displayBody, "keep me")
    }

    func testPageResyncFlag() throws {
        let json = #"{"events":[],"resync":true}"#
        let page = try JSONDecoder().decode(SessionEventsPage.self, from: Data(json.utf8))
        XCTAssertTrue(page.resync)
        XCTAssertTrue(page.events.isEmpty)
    }

    func testSessionSSEDecoderEmitsEventAndResync() {
        let decoder = JSONDecoder()
        var sse = SessionSSEDecoder(decoder: decoder)

        XCTAssertNil(sse.consume(line: "id: 3"))
        XCTAssertNil(sse.consume(line: "event: session_event"))
        XCTAssertNil(sse.consume(line: #"data: {"id":"e3","session_id":"s","sequence":3,"kind":"message","created_at":"2026-08-14T09:00:00Z"}"#))
        guard case let .event(event)? = sse.consume(line: "") else {
            return XCTFail("expected session_event frame")
        }
        XCTAssertEqual(event.sequence, 3)

        XCTAssertNil(sse.consume(line: "event: resync"))
        XCTAssertNil(sse.consume(line: #"data: {"resync":true}"#))
        guard case .resync? = sse.consume(line: "") else {
            return XCTFail("expected resync frame")
        }
    }
}
