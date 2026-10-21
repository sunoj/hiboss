// Verifies native share payloads and PDF parsing states with real local documents.
// Exercises Box actions through the authenticated demo media boundary.
// Dependencies: XCTest, PDFKit, HibossKit and HiBoss.

import HibossKit
import PDFKit
import UIKit
import XCTest
@testable import HiBoss

@MainActor
final class BoxShareContentTests: XCTestCase {
    func testTextAndLinkShareTheirContent() throws {
        let media = BoxMediaStore(api: nil)
        let text = item(.text)
        XCTAssertEqual(text.shareContent(media: media) as? [String], ["Fixture"])
        let link = item(.link)
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        XCTAssertEqual(link.shareContent(media: media) as? [URL], [url])
    }

    func testMediaKindsNeverFallBackToSharingTheirFilename() {
        let media = BoxMediaStore(api: nil)
        for kind: BoxItem.Kind in [.image, .video, .file] {
            XCTAssertTrue(item(kind).shareContent(media: media).isEmpty)
        }
    }

    func testEveryMediaKindSharesDownloadedURLAndNothingBeforeDownload() async throws {
        let api = DemoBoxAPI()
        let media = BoxMediaStore(api: api)
        for kind: BoxItem.Kind in [.image, .video, .file] {
            let fixture = try XCTUnwrap(DemoBoxAPI.fixtures.first { $0.kind == kind })
            XCTAssertTrue(fixture.shareContent(media: media).isEmpty)
            await media.load(fixture)
            let resource = try XCTUnwrap(media.resources[fixture.id])
            XCTAssertEqual(fixture.shareContent(media: media) as? [URL], [resource.url])
        }
    }

    func testPDFRenderingRunsOffMainThreadAndDistinguishesLockedAndCorrupt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let valid = directory.appendingPathComponent("valid.pdf")
        let locked = directory.appendingPathComponent("locked.pdf")
        let corrupt = directory.appendingPathComponent("corrupt.pdf")
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
            .pdfData { $0.beginPage() }
        try data.write(to: valid)
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertTrue(document.write(to: locked, withOptions: [
            .userPasswordOption: "fixture-password", .ownerPasswordOption: "fixture-owner",
        ]))
        try Data("Invalid PDF".utf8).write(to: corrupt)
        let results = await Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            return [valid, locked, corrupt].map(BoxPDFPreview.load)
        }.value
        XCTAssertNotNil(results[0].page)
        XCTAssertFalse(results[0].unreadable)
        XCTAssertTrue(results[1].locked)
        XCTAssertFalse(results[1].unreadable)
        XCTAssertNil(results[1].page)
        XCTAssertTrue(results[2].unreadable)
        XCTAssertFalse(results[2].locked)
    }

    private func item(_ kind: BoxItem.Kind) -> BoxItem {
        BoxItem(id: "fixture", bossID: "boss", bossName: "Boss", kind: kind,
                text: "Fixture", url: kind == .link ? "https://example.com" : nil,
                createdAt: "2026-01-01T00:00:00Z")
    }
}
