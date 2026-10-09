// Verifies attachment propagation into the macOS full-body presentation models.
// Exports: MessageAttachmentTests for History, attention, and island messages.
// Dependencies: XCTest, HibossKit message metadata, and HibossIsland reading models.

import HibossKit
import XCTest
@testable import HibossIsland

final class MessageAttachmentTests: XCTestCase {
    func testImageAttachmentSurvivesLongHistoryPreviewAndAttentionConversion() {
        let message = message(fileURL: "https://hiboss.mings.work/api/attachments/example.png",
            body: String(repeating: "Result. ", count: 200))
        let content = HistoryReadingContent(message: message)
        XCTAssertTrue(content.isLong)
        XCTAssertEqual(content.fullText, message.body + "\n\nSupporting details")
        XCTAssertEqual(content.attachment?.kind, .image)
        XCTAssertEqual(content.attachment?.filename, "example.png")
        XCTAssertEqual(content.attachment?.url.absoluteString, message.metadata?.fileURL)
        let item = AttentionItem(message: message)
        XCTAssertEqual(item.attachment, content.attachment)
        XCTAssertEqual(item.asOptionMessage.metadata?.attachment, content.attachment)
    }

    func testFileAttachmentIsAvailableEvenWithAnEmptyBody() {
        let message = message(fileURL: "https://example.com/report%20final.pdf", body: "")
        let content = HistoryReadingContent(message: message)
        XCTAssertEqual(content.attachment?.kind, .file)
        XCTAssertEqual(content.attachment?.filename, "report final.pdf")
        XCTAssertEqual(AttentionItem(message: message).attachment, content.attachment)
    }

    func testMissingAndInvalidAttachmentsRemainAbsent() {
        for fileURL in [nil, "file:///tmp/private.png", "javascript:alert(1)"] as [String?] {
            let message = message(fileURL: fileURL)
            XCTAssertNil(HistoryReadingContent(message: message).attachment)
            XCTAssertNil(AttentionItem(message: message).attachment)
        }
    }

    private func message(fileURL: String?, body: String = "Result") -> HistoryMessage {
        HistoryMessage(id: "attachment", body: body, agentName: "Agent",
            direction: "agent_to_boss", status: "delivered", priority: "normal",
            metadata: MessageMetadata(options: [], content: "Supporting details", fileURL: fileURL),
            createdAt: "2026-10-09 10:00:00")
    }
}
