// Verifies inline reading policy for ordinary, long, and searched messages.
// Exports: HistoryReadingTests; no native UI or E2E execution.
// Dependencies: XCTest and HistoryReadingContent.

import XCTest
import HibossKit
@testable import HibossIsland

final class HistoryReadingTests: XCTestCase {
    func testOrdinaryMessageRemainsFullyVisible() {
        let content = HistoryReadingContent(body: "First paragraph.\n\nSecond paragraph.", content: nil)
        XCTAssertFalse(content.isLong)
        XCTAssertEqual(content.preview, content.fullText)
    }

    func testSupportingContentIsReadableAlongsideTheBody() {
        let content = HistoryReadingContent(body: "Result", content: "Details\nSecond line")
        XCTAssertEqual(content.fullText, "Result\n\nDetails\nSecond line")
    }

    func testLongSingleLineGetsAShortPreviewWithoutLosingFullText() {
        let text = String(repeating: "Long message. ", count: 150)
        let content = HistoryReadingContent(body: text, content: nil)
        XCTAssertTrue(content.isLong)
        XCTAssertLessThan(content.preview.count, content.fullText.count)
        XCTAssertEqual(content.fullText, text)
    }

    func testManyShortLinesAreCollapsedEvenWithFewCharacters() {
        let text = (1...30).map { "Line \($0)" }.joined(separator: "\n")
        let content = HistoryReadingContent(body: text, content: nil)
        XCTAssertTrue(content.isLong)
        XCTAssertFalse(content.preview.contains("Line 30"))
        XCTAssertTrue(content.fullText.contains("Line 30"))
    }

    func testUnicodePreviewDoesNotBreakComposedCharacters() {
        let content = HistoryReadingContent(body: String(repeating: "👨‍👩‍👧‍👦", count: 1_300), content: nil)
        XCTAssertTrue(content.isLong)
        XCTAssertEqual(content.preview.first, "👨‍👩‍👧‍👦")
        XCTAssertTrue(content.preview.hasSuffix("…"))
    }

    func testEmptySupportingContentDoesNotAddBlankParagraphs() {
        XCTAssertEqual(HistoryReadingContent(body: "Result", content: " \n ").fullText, "Result")
    }

    func testContentThresholdIncludesSupportingDetails() {
        let content = HistoryReadingContent(body: "Result", content: String(repeating: "x", count: 1_300))
        XCTAssertTrue(content.isLong)
    }

    func testSearchFindsSupportingTextPreviouslyHiddenBehindDetails() {
        let message = HistoryMessage(id: "details", body: "Result", agentName: "Agent",
            direction: "agent_to_boss", status: "delivered", priority: "normal",
            metadata: MessageMetadata(options: [], content: "The retry recovered the deployment."),
            createdAt: "2026-09-22 10:00:00")
        XCTAssertTrue(message.matchesHistorySearch("retry recovered"))
        XCTAssertFalse(message.matchesHistorySearch("missing result"))
    }
}
