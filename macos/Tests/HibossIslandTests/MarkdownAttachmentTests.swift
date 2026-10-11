// Checks filename discovery, bounded document loading, and table parsing for Markdown uploads.
// Exports: MarkdownAttachmentTests using synthetic loopback attachment responses.
// Dependencies: XCTest, MarkdownAttachmentServer, and native document reading models.

import Foundation
import XCTest
@testable import HibossIsland

@MainActor
final class MarkdownAttachmentTests: XCTestCase {
    func testExtensionlessOctetStreamAttachmentUsesResponseFilenameAndLoadsMarkdown() async throws {
        let server = MarkdownAttachmentServer()
        defer { server.stop() }
        try await server.start()
        let url = try XCTUnwrap(URL(string: server.baseURL + "/uploaded-id"))
        XCTAssertFalse(MarkdownAttachmentInfo(url: url).isMarkdown)
        let info = try await MarkdownAttachmentDocument.inspect(url)
        XCTAssertEqual(info.filename, "report final.md")
        XCTAssertTrue(info.isMarkdown)
        let document = try await MarkdownAttachmentDocument.read(url)
        XCTAssertEqual(document, MarkdownAttachmentServer.source)
    }

    func testUnavailableBinaryAndOversizedDocumentsFailExplicitly() async throws {
        let server = MarkdownAttachmentServer()
        defer { server.stop() }
        try await server.start()
        for path in ["/unavailable", "/binary.md", "/large.md"] {
            let url = try XCTUnwrap(URL(string: server.baseURL + path))
            do {
                _ = try await MarkdownAttachmentDocument.read(url)
                XCTFail("Unexpected preview for \(path)")
            } catch is MarkdownAttachmentDocument.DocumentError {
                // A file link remains available when an inline preview cannot be read.
            }
        }
    }

    func testTablesPreserveAlignmentEscapedPipesAndSurroundingMarkdown() throws {
        let sections = MarkdownDocumentSections.parse("""
        # Summary
        | Name | Value | State |
        | :--- | ---: | :---: |
        | A\\|B | **345** | Ready |

        Final paragraph.
        """)
        XCTAssertEqual(sections.count, 3)
        guard case .table(let table) = sections[1] else { return XCTFail("Missing table") }
        XCTAssertEqual(table.header, ["Name", "Value", "State"])
        XCTAssertEqual(table.alignments, [.leading, .trailing, .center])
        XCTAssertEqual(table.rows, [["A|B", "**345**", "Ready"]])
    }

    func testFencedTablesAndOrdinaryPipeTextRemainText() {
        for source in ["~~~md\n| A | B |\n| --- | --- |\n~~~", "A | B\nparagraph | text"] {
            XCTAssertEqual(MarkdownDocumentSections.parse(source), [.text(source)])
        }
    }
}
