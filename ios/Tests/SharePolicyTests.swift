// Covers supported item detection and exact media/text size boundaries.
// Exports SharePolicyTests including mixed representation precedence.
// Dependencies: XCTest, UniformTypeIdentifiers and the HiBoss share core.

import UniformTypeIdentifiers
import XCTest
@testable import HiBoss

final class SharePolicyTests: XCTestCase {
    func testTypeDetectionUsesConformanceAndPrefersMediaOverFileURLs() {
        XCTAssertEqual(ShareAttachment.type(in: [UTType.jpeg.identifier, UTType.fileURL.identifier]), .image)
        XCTAssertEqual(ShareAttachment.type(in: [UTType.mpeg4Movie.identifier, UTType.url.identifier]),
            .movie)
        XCTAssertEqual(ShareAttachment.type(in: [UTType.url.identifier, UTType.plainText.identifier]), .url)
        XCTAssertEqual(ShareAttachment.type(in: [UTType.utf8PlainText.identifier]), .plainText)
        XCTAssertNil(ShareAttachment.type(in: [UTType.pdf.identifier]))
        XCTAssertNil(ShareAttachment.type(in: []))
    }

    func testOnlyWholeHTTPURLsAreLinks() {
        for value in ["https://example.com/page?q=1", "  http://example.com  "] {
            XCTAssertEqual(ShareAttachment.text(value).kind, .link)
        }
        for value in ["Read https://example.com", "file:///private/example", "hello", "https://", ""] {
            XCTAssertEqual(ShareAttachment.text(value).kind, .text)
        }
    }

    func testImageBoundariesAndCompressionRefusal() {
        XCTAssertEqual(SharePolicy.decision(kind: .image, bytes: 0), .refuse)
        XCTAssertEqual(SharePolicy.decision(kind: .image, bytes: SharePolicy.imageBytes), .upload)
        XCTAssertEqual(SharePolicy.decision(kind: .image, bytes: SharePolicy.imageBytes + 1), .compress)
        XCTAssertEqual(SharePolicy.decision(kind: .image, bytes: SharePolicy.imageBytes + 1,
            prepared: true), .refuse)
    }

    func testVideoAlwaysExportsFirstThenUsesFiftyMBBoundary() {
        XCTAssertEqual(SharePolicy.decision(kind: .video, bytes: 1), .compress)
        XCTAssertEqual(SharePolicy.decision(kind: .video, bytes: SharePolicy.videoBytes + 1), .compress)
        XCTAssertEqual(SharePolicy.decision(kind: .video, bytes: SharePolicy.videoBytes, prepared: true),
            .upload)
        XCTAssertEqual(SharePolicy.decision(kind: .video, bytes: SharePolicy.videoBytes + 1,
            prepared: true), .refuse)
    }

    func testTextLimitsUseBytesAndFilesAreRefused() {
        XCTAssertEqual(SharePolicy.decision(kind: .text, bytes: SharePolicy.textBytes), .upload)
        XCTAssertEqual(SharePolicy.decision(kind: .text, bytes: SharePolicy.textBytes + 1), .refuse)
        XCTAssertEqual(SharePolicy.decision(kind: .link, bytes: 8192), .upload)
        XCTAssertEqual(SharePolicy.decision(kind: .link, bytes: 8193), .refuse)
        XCTAssertEqual(SharePolicy.decision(kind: .file, bytes: 1), .refuse)
    }

    @MainActor func testLoaderRejectsNoAttachmentsAndMoreThanFour() async throws {
        for providers in [[], Array(repeating: NSItemProvider(), count: 5)] {
            do {
                _ = try await ShareAttachmentLoader.load(providers, directory: URL(fileURLWithPath: "/tmp"))
                XCTFail("Invalid provider counts must be refused")
            } catch { XCTAssertTrue(error is ShareError) }
        }
    }
}
