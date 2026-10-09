// Covers decoding `metadata.file_url` into a MessageAttachment.
// The real payload shape is what `hiboss send --file` stores on the server.

import XCTest
@testable import HibossKit

final class MessageAttachmentTests: XCTestCase {
    private func metadata(_ json: String) throws -> MessageMetadata {
        try JSONDecoder().decode(MessageMetadata.self, from: Data(json.utf8))
    }

    func testUploadedImageDecodesAsImageAttachment() throws {
        let decoded = try metadata(
            #"{"file_url":"https://hiboss.mings.work/api/attachments/ac2d4528.png"}"#
        )
        let attachment = try XCTUnwrap(decoded.attachment)
        XCTAssertEqual(attachment.kind, .image)
        XCTAssertEqual(attachment.filename, "ac2d4528.png")
        XCTAssertEqual(attachment.url.absoluteString, "https://hiboss.mings.work/api/attachments/ac2d4528.png")
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
}
