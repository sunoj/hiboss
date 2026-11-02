// Verifies bounded note uploads, GIF preservation and visible validation failures.
// Uses UIKit image fixtures and the app's ImageIO preparation path.
import HibossKit
import UIKit
import XCTest
@testable import HiBoss

final class SessionNoteImageTests: XCTestCase {
    func testReplyQuoteUsesFirstLineAndExactMessageID() {
        let reply = SessionNoteReply(messageID: "m1", body: "Ready", agentName: "worker",
                                     createdAt: "2026-11-02 09:00:00")
        let note = SessionNote(id: "n1", sessionID: "s1", agentID: "a1", bossName: "Alex",
                               body: "Check\nSecond line", status: .read,
                               createdAt: reply.createdAt, replies: [reply])
        XCTAssertEqual(SessionNoteQuote.text(for: "m1", notes: [note]), "Check")
        XCTAssertNil(SessionNoteQuote.text(for: "m", notes: [note]))
        XCTAssertNil(SessionNoteQuote.text(for: "m1", notes: []))
    }

    func testDownscalesAndEncodesJPEG() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 1500))
        let original = renderer.image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3000, height: 1500))
        }
        let upload = try SessionNoteImagePreparation.prepare(XCTUnwrap(original.pngData()))
        let decoded = try XCTUnwrap(UIImage(data: upload.data)?.cgImage)
        XCTAssertEqual(upload.contentType, "image/jpeg")
        XCTAssertEqual(max(decoded.width, decoded.height), 2048)
        XCTAssertEqual(upload.data.prefix(2), Data([0xff, 0xd8]))
    }

    func testGIFBytesStayUnchanged() throws {
        let gif = Data("GIF89a-fixture".utf8)
        let upload = try SessionNoteImagePreparation.prepare(gif)
        XCTAssertEqual(upload.contentType, "image/gif")
        XCTAssertEqual(upload.data, gif)
    }

    func testRejectsOversizedGIFWithVisibleError() {
        var gif = Data("GIF89a".utf8)
        gif.append(Data(repeating: 0, count: 10 * 1024 * 1024))
        XCTAssertThrowsError(try SessionNoteImagePreparation.prepare(gif)) { error in
            XCTAssertEqual(error.localizedDescription, String(localized: "Image exceeds 10 MB"))
        }
    }

    func testRejectsInvalidImage() {
        XCTAssertThrowsError(try SessionNoteImagePreparation.prepare(Data("invalid".utf8)))
    }
}
