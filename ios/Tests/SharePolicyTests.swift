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
        XCTAssertEqual(ShareAttachment.type(in: [UTType.pdf.identifier]), .pdf)
        XCTAssertEqual(ShareAttachment.type(in: [UTType.fileURL.identifier, UTType.url.identifier]), .fileURL)
        XCTAssertNil(ShareAttachment.type(in: []))
    }

    func testOnlyWholeHTTPURLsAreLinks() {
        for value in ["https://example.com/page?q=1", "  http://example.com  "] {
            XCTAssertEqual(ShareAttachment.text(value).kind, .link)
        }
        XCTAssertEqual(ShareAttachment.text("file:///private/example.pdf").kind, .file)
        for value in ["Read https://example.com", "hello", "https://", ""] {
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

    func testTextLimitsUseBytes() {
        XCTAssertEqual(SharePolicy.decision(kind: .text, bytes: SharePolicy.textBytes), .upload)
        XCTAssertEqual(SharePolicy.decision(kind: .text, bytes: SharePolicy.textBytes + 1), .refuse)
        XCTAssertEqual(SharePolicy.decision(kind: .link, bytes: 8192), .upload)
        XCTAssertEqual(SharePolicy.decision(kind: .link, bytes: 8193), .refuse)
    }

    func testFilesUploadUnchangedThroughFiftyMBAndRefuseLargerFiles() {
        let limit = 50 * 1024 * 1024
        XCTAssertEqual(SharePolicy.decision(kind: .file, bytes: 1), .upload)
        XCTAssertEqual(SharePolicy.decision(kind: .file, bytes: limit), .upload)
        XCTAssertEqual(SharePolicy.decision(kind: .file, bytes: limit + 1), .refuse)
        XCTAssertEqual(SharePolicy.decision(kind: .file, bytes: limit, prepared: true), .upload)
    }

    @MainActor func testLoaderRejectsNoAttachmentsAndMoreThanFour() async throws {
        for providers in [[], Array(repeating: NSItemProvider(), count: 5)] {
            do {
                _ = try await ShareAttachmentLoader.load(providers, directory: URL(fileURLWithPath: "/tmp"))
                XCTFail("Invalid provider counts must be refused")
            } catch { XCTAssertTrue(error is ShareError) }
        }
    }

    func testActivationPredicateAllowsOneToFourPublicItemsAcrossExtensionItems() throws {
        let plugins = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
        let data = try Data(contentsOf: plugins.appendingPathComponent("HiBossShare.appex/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil)
            as? [String: Any])
        let ext = try XCTUnwrap(plist["NSExtension"] as? [String: Any])
        let attributes = try XCTUnwrap(ext["NSExtensionAttributes"] as? [String: Any])
        let rule = try XCTUnwrap(attributes["NSExtensionActivationRule"] as? String)
        XCTAssertFalse(rule.contains("TRUEPREDICATE"))
        let predicate = NSPredicate(format: rule)
        let types: [UTType] = [.pdf, .zip, .mp3, .url, .plainText, .image, .movie, .fileURL, .item]
        for type in types {
            let attachment = ["registeredTypeIdentifiers": [type.identifier]]
            for count in 0...5 {
                let items = [["attachments": Array(repeating: attachment, count: count)]]
                XCTAssertEqual(predicate.evaluate(with: ["extensionItems": items]), (1...4).contains(count))
            }
        }
        let attachment = ["registeredTypeIdentifiers": [UTType.pdf.identifier]]
        let items = Array(repeating: ["attachments": [attachment]], count: 4)
        XCTAssertTrue(predicate.evaluate(with: ["extensionItems": items]))
        XCTAssertFalse(predicate.evaluate(with: ["extensionItems": items + items]))
        let unsupported = [["attachments": [["registeredTypeIdentifiers": ["invalid.type"]]]]]
        XCTAssertFalse(predicate.evaluate(with: ["extensionItems": unsupported]))
    }
}
