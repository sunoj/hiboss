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

    func testCopyFenceKeepsTheExactTextAndOptionalLabel() {
        let command = "  rbox submit tencent-sg . -- npm test \\\n    --run  "
        let blocks = MessageMarkdown.blocks("Run this:\n\n```copy Deploy command\n\(command)\n```\n```copy\n0xAbC\n```")
        XCTAssertEqual(blocks.map(\.kind), [.paragraph, .copy(label: "Deploy command"), .copy(label: nil)])
        XCTAssertEqual(blocks[1].text, command)
        XCTAssertEqual(blocks[2].text, "0xAbC")
        XCTAssertEqual(MessageMarkdown.blocks("~~~copy\ta label\nx\n~~~").first?.kind, .copy(label: "a label"))
    }

    func testOnlyTheCopyInfoWordMakesACopyBlock() {
        for info in ["copyright", "copy-foo", "Copy", "sh copy", ""] {
            XCTAssertEqual(MessageMarkdown.blocks("```\(info)\nx\n```").first?.kind, .code, info)
        }
    }

    func testUnclosedCopyFenceFromACutPreviewOffersNoCopy() {
        XCTAssertEqual(MessageMarkdown.blocks("```copy Key\nsk-partial…"),
                       [.init(kind: .code, text: "sk-partial…")])
    }

    func testCRLFContentCopiesWithoutBlankLines() {
        XCTAssertEqual(MessageMarkdown.blocks("```copy\r\na\r\nb\r\n```").first?.text, "a\nb")
    }

    @MainActor func testCopyButtonWritesTheDisplayedText() {
        let original = MessagePasteboard.write
        defer { MessagePasteboard.write = original }
        var copied: [String] = []
        MessagePasteboard.write = { copied.append($0) }
        let block = MessageMarkdown.blocks("```copy\n line one\n\nline three \n```")[0]
        CopyableTextBlock.copy(block.text)
        XCTAssertEqual(copied, [" line one\n\nline three "])
    }
}
