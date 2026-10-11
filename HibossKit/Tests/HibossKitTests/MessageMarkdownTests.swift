// Verifies Markdown content structure and preservation of historical long messages.
// Exercises the native presentation contract with Unicode titles and selectable text.

import XCTest
@testable import HibossKit

final class MessageMarkdownTests: XCTestCase {
    func testLongStoredTitleIsBoundedAndItsOriginalTextMovesIntoReadableContent() {
        let original = String(repeating: "🏠", count: 145)
        let text = MessageText(body: original, content: "**Complete** report")
        XCTAssertEqual(text.title.unicodeScalars.count, 144)
        XCTAssertEqual(text.content, original + "\n\n**Complete** report")
        XCTAssertEqual(MessageText(body: "Ready", content: nil).title, "Ready")
        XCTAssertNil(MessageText(body: "Ready", content: " ").content)
    }

    func testMarkdownPreservesParagraphsListsQuotesAndCodeWhitespace() {
        let source = "# Result\n\nFirst **paragraph**\nnext line\n\n- Ready\n2. Verify\n> Evidence\n```swift\n  let x = 1\n\n  print(x)\n```"
        let blocks = MessageMarkdown.blocks(source)
        XCTAssertEqual(blocks.map(\.kind), [.heading(1), .paragraph, .item("•"), .item("2."), .quote, .code])
        XCTAssertEqual(blocks[1].text, "First **paragraph**\nnext line")
        XCTAssertEqual(blocks[5].text, "  let x = 1\n\n  print(x)")
    }

    func testInlineMarkdownFormatsEmphasisAndLinksWithoutLosingLineBreaks() {
        let text = MessageMarkdown.inline("**Ready**\n[Evidence](https://example.com) and `code`")
        XCTAssertEqual(String(text.characters), "Ready\nEvidence and code")
        XCTAssertTrue(text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        XCTAssertTrue(text.runs.contains { $0.link?.absoluteString == "https://example.com" })
        XCTAssertFalse(MessageMarkdown.inline("[local](file:///private/unused)").runs.contains { $0.link != nil })
    }

    func testUnclosedFenceAndLiteralHTMLRemainReadable() {
        XCTAssertEqual(MessageMarkdown.blocks("```\n<plain>\n"), [.init(kind: .code, text: "<plain>\n")])
        XCTAssertEqual(MessageMarkdown.blocks("<script>literal</script>").first?.text, "<script>literal</script>")
    }
}
