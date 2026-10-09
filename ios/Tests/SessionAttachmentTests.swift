// Validates attachment resolution for transcript messages outside the loaded history window.
// Exports: SessionAttachmentTests covering image/file URLs and rejected payloads.
// Dependencies: XCTest, HibossKit and the iOS SessionEvent attachment extension.

import HibossKit
import XCTest
@testable import HiBoss

final class SessionAttachmentTests: XCTestCase {
    func testUncachedStreamMessagePreservesImageAttachment() {
        let event = message(url: "https://example.com/banner.PNG?version=2")
        XCTAssertEqual(event.messageAttachment?.kind, .image)
        XCTAssertEqual(event.messageAttachment?.filename, "banner.PNG")
        XCTAssertEqual(event.messageAttachment?.url.absoluteString,
                       "https://example.com/banner.PNG?version=2")
    }

    func testUncachedStreamMessagePreservesFileAttachment() {
        let event = message(url: "https://example.com/release-notes.pdf")
        XCTAssertEqual(event.messageAttachment?.kind, .file)
        XCTAssertEqual(event.messageAttachment?.filename, "release-notes.pdf")
    }

    func testOnlyAgentMessagesRenderAttachments() {
        XCTAssertNil(message(url: "https://example.com/banner.png", direction: "boss_to_agent")
            .messageAttachment)
        XCTAssertNil(message(url: "https://example.com/banner.png", kind: "tool_result")
            .messageAttachment)
    }

    func testMalformedMissingAndUnsafeURLsAreIgnored() {
        for url in ["", "file:///private/banner.png", "javascript:alert(1)", "https:///banner.png"] {
            XCTAssertNil(message(url: url).messageAttachment)
        }
        let event = SessionEvent(id: "empty", sessionId: "session", sequence: 1, kind: "message",
                                 direction: "agent_to_boss", payload: .object([:]), createdAt: "")
        XCTAssertNil(event.messageAttachment)
    }

    private func message(url: String, direction: String = "agent_to_boss",
                         kind: String = "message") -> SessionEvent {
        SessionEvent(id: "event", sessionId: "session", sequence: 1, kind: kind,
                     direction: direction,
                     payload: .object(["metadata": .object(["file_url": .string(url)])]), createdAt: "")
    }
}
