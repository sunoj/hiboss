// Covers image extraction, source preservation and code boundaries in iOS Markdown galleries.
// Exports MediaMarkdownTests; document URLs resolve relative references without changing text rendering.
// Dependencies: XCTest and the HiBoss app target.

import XCTest
@testable import HiBoss

final class MediaMarkdownTests: XCTestCase {
    func testImagesKeepOrderTitlesCaptionsAndSurroundingText() {
        let source = #"Before ![First](https://example.com/first.png "Caption")"#
            + #" between ![Second](https://example.com/second.png) after"#
        let segments = MediaMarkdown.segments(source)
        let images = segments.compactMap {
            if case let .image(item) = $0 { return item }
            return nil
        }
        XCTAssertEqual(images.map(\.title), ["First", "Second"])
        XCTAssertEqual(images.map(\.caption), ["Caption", nil])
        let texts = segments.compactMap {
            if case let .text(text) = $0 { return text }
            return nil
        }
        XCTAssertEqual(texts, ["Before ", " between ", " after\n"])
    }

    func testFencedAndInlineCodeNeverBecomeImages() {
        let source = """
        ```markdown
        ![Code](https://example.com/code.png)
        ```
        `![Inline](https://example.com/inline.png)`
        ![Actual](https://example.com/actual.png)
        """
        let images = MediaMarkdown.segments(source).compactMap {
            if case let .image(item) = $0 { return item }
            return nil
        }
        XCTAssertEqual(images.map(\.title), ["Actual"])
    }

    func testDocumentImagesResolveAgainstOriginalURL() {
        let base = URL(string: "https://example.com/reports/release.md")!
        let segments = MediaMarkdown.segments("![Banner](images/banner.png)", baseURL: base)
        guard case let .image(item) = segments.first else { return XCTFail("relative image missing") }
        XCTAssertEqual(item.url.absoluteString, "https://example.com/reports/images/banner.png")
    }

    func testUnsupportedSchemesAndPlainTablesRemainText() {
        let source = "![Bad](javascript:alert)\n| Name | Value |\n| --- | --- |\n| A | B |"
        let segments = MediaMarkdown.segments(source)
        XCTAssertEqual(segments.count, 1)
        guard case let .text(text) = segments.first else { return XCTFail("text missing") }
        XCTAssertEqual(text, source + "\n")
    }
}
