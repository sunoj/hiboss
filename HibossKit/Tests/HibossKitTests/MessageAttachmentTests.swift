// Covers decoding `metadata.file_url` and `file_thumbnail_url` into a MessageAttachment.
// The real payload shape is what `hiboss send --file` stores on the server.

import XCTest
@testable import HibossKit

final class MessageAttachmentTests: XCTestCase {
    private func metadata(_ json: String) throws -> MessageMetadata {
        try JSONDecoder().decode(MessageMetadata.self, from: Data(json.utf8))
    }

    func testUploadedImageDecodesAsImageAttachment() throws {
        let decoded = try metadata(
            #"{"file_url":"https://hiboss.example/api/attachments/ac2d4528.png"}"#
        )
        let attachment = try XCTUnwrap(decoded.attachment)
        XCTAssertEqual(attachment.kind, .image)
        XCTAssertEqual(attachment.filename, "ac2d4528.png")
        XCTAssertEqual(attachment.url.absoluteString, "https://hiboss.example/api/attachments/ac2d4528.png")
    }

    func testNonImageDecodesAsFileAttachment() throws {
        let decoded = try metadata(#"{"file_url":"https://example.com/report.PDF"}"#)
        XCTAssertEqual(decoded.attachment?.kind, .file)
    }

    func testUppercaseImageExtensionIsImage() {
        XCTAssertEqual(MessageAttachment(urlString: "https://example.com/a.JPEG")?.kind, .image)
    }

    func testNonHTTPAndRelativeURLsAreRejected() {
        XCTAssertNil(MessageAttachment(urlString: "file:///etc/passwd"))
        XCTAssertNil(MessageAttachment(urlString: "javascript:alert(1)"))
        XCTAssertNil(MessageAttachment(urlString: "/api/attachments/x.png"))
        XCTAssertNil(MessageAttachment(urlString: ""))
    }

    func testNonStringFileURLDoesNotFailTheMessage() throws {
        let decoded = try metadata(#"{"options":["Keep"],"file_url":42}"#)
        XCTAssertEqual(decoded.options, ["Keep"])
        XCTAssertNil(decoded.attachment)
    }

    func testAbsentFileURLHasNoAttachmentAndDoesNotEncode() throws {
        let decoded = try metadata(#"{"options":[]}"#)
        XCTAssertNil(decoded.attachment)
        let encoded = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)
        XCTAssertFalse(encoded.contains("file_url"))
    }

    func testFileURLRoundTrips() throws {
        let decoded = try metadata(#"{"file_url":"https://example.com/a.png"}"#)
        let again = try JSONDecoder().decode(MessageMetadata.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(again, decoded)
    }

    func testThumbnailIsPreferredForDisplayWhenPresent() throws {
        let decoded = try metadata(#"""
            {"file_url":"https://hiboss.example/api/attachments/a.png",
             "file_thumbnail_url":"https://hiboss.example/api/attachments/a.thumb.jpg"}
            """#)
        let attachment = try XCTUnwrap(decoded.attachment)
        XCTAssertEqual(attachment.url.absoluteString, "https://hiboss.example/api/attachments/a.png")
        XCTAssertEqual(attachment.displayURL.absoluteString, "https://hiboss.example/api/attachments/a.thumb.jpg")
        let again = try JSONDecoder().decode(MessageMetadata.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(again.fileThumbnailURL, decoded.fileThumbnailURL)
    }

    func testOriginalIsShownWithoutAValidThumbnail() throws {
        let plain = try metadata(#"{"file_url":"https://example.com/a.png"}"#)
        let absent = try XCTUnwrap(plain.attachment)
        XCTAssertNil(absent.thumbnailURL)
        XCTAssertEqual(absent.displayURL.absoluteString, "https://example.com/a.png")
        let wrongType = try metadata(#"{"file_url":"https://example.com/a.png","file_thumbnail_url":7}"#)
        XCTAssertEqual(wrongType.attachment?.displayURL.absoluteString, "https://example.com/a.png")
        let unsafe = try metadata(#"{"file_url":"https://example.com/a.png","file_thumbnail_url":"file:///x"}"#)
        XCTAssertNil(unsafe.attachment?.thumbnailURL)
        let encoded = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        XCTAssertFalse(encoded.contains("file_thumbnail_url"))
    }

    func testOptionMediaPrefersItsThumbnail() throws {
        let decoded = try metadata(#"""
            {"options":["A","B"],"option_media":[
              {"label":"A","url":"https://example.com/a.png","thumbnail_url":"https://example.com/a.jpg"},
              {"label":"B","url":"https://example.com/b.png"}]}
            """#)
        XCTAssertEqual(decoded.optionMedia.map(\.displayURL), ["https://example.com/a.jpg", "https://example.com/b.png"])
        XCTAssertNil(decoded.optionMedia[1].thumbnailURL)
        let again = try JSONDecoder().decode(MessageMetadata.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(again, decoded)
    }
}
