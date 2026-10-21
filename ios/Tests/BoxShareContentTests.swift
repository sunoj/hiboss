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

    func testDownloadedMediaKeepsHumanNamesAndRemovesDirectories() async throws {
        let media = BoxMediaStore(api: DemoBoxAPI())
        for (id, name) in [("demo-image", "Layout reference.png"),
                           ("demo-video", "Motion reference.mp4"), ("demo-file", "Reference.txt")] {
            let fixture = try XCTUnwrap(DemoBoxAPI.fixtures.first { $0.id == id })
            await media.load(fixture)
            let url = try XCTUnwrap(media.resources[id]?.url)
            XCTAssertEqual(url.lastPathComponent, name)
            XCTAssertTrue(url.deletingLastPathComponent().lastPathComponent.hasPrefix("box-"))
            media.remove(id: id)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        }
    }

    func testEmptyAndHostileDownloadNamesStaySafeAndBounded() async throws {
        for name in [nil, "", "../x", ".", "/", String(repeating: "a", count: 300),
                     String(repeating: "👩🏽‍💻", count: 100), "photo\\name", "\u{0}hidden"] as [String?] {
            let fixture = downloadItem(name: name, type: "application/pdf")
            let media = BoxMediaStore(api: FilenameBoxAPI(data: Data("%PDF-1.7".utf8)))
            await media.load(fixture)
            let url = try XCTUnwrap(media.resources[fixture.id]?.url)
            let filename = url.lastPathComponent
            XCTAssertFalse(filename.hasPrefix("."))
            XCTAssertFalse(filename.contains("/"))
            XCTAssertFalse(filename.contains("\\"))
            XCTAssertLessThanOrEqual(filename.utf8.count, 240)
            XCTAssertFalse(url.deletingPathExtension().lastPathComponent.isEmpty)
            XCTAssertEqual(url.pathExtension, "pdf")
            if name == nil || name == "" { XCTAssertEqual(filename, "File.pdf") }
        }
    }

    func testExtensionPrecedenceAndCommonByteSignatures() async throws {
        let cases: [(String?, String?, Data, String)] = [
            (nil, "application/unknown", Data("%PDF-1.7".utf8), "File.pdf"),
            (nil, nil, Data([137, 80, 78, 71, 13, 10, 26, 10]), "File.png"),
            ("Photo", nil, Data([255, 216, 255]), "Photo.jpg"),
            ("Animation", nil, Data("GIF89a".utf8), "Animation.gif"),
            ("Clip", nil, Data([0, 0, 0, 20] + Array("ftypisom".utf8)), "Clip.mp4"),
            ("Clip", nil, Data([0, 0, 0, 20] + Array("ftypqt  ".utf8)), "Clip.mov"),
            ("Archive", nil, Data([80, 75, 3, 4]), "Archive.zip"),
            ("Report.custom", nil, Data("%PDF-1.7".utf8), "Report.custom"),
            ("Report.txt", "application/pdf", Data(), "Report.pdf"),
            ("Mystery", "application/octet-stream", Data(), "Mystery.bin"),
            ("Screenshot 2026-10-21 at 9.37.12", "image/png", Data(), "Screenshot 2026-10-21 at 9.37.12.png"),
            ("Screenshot 2026-10-21 at 9.37.12", nil, Data([137, 80, 78, 71, 13, 10, 26, 10]),
             "Screenshot 2026-10-21 at 9.37.12.png"),
            ("Meeting v1.2 notes", "application/pdf", Data(), "Meeting v1.2 notes.pdf"),
            ("archive.tar.gz", "application/x-hiboss-unknown", Data(), "archive.tar.gz"),
            ("report.PDF", "application/pdf", Data(), "report.pdf"),
            ("Recording.mp3", nil, Data(), "Recording.mp3"),
            ("Reference.hibossfixture", "application/octet-stream", Data(), "Reference.hibossfixture"),
        ]
        for (name, type, data, expected) in cases {
            let fixture = downloadItem(name: name, type: type)
            let media = BoxMediaStore(api: FilenameBoxAPI(data: data))
            await media.load(fixture)
            XCTAssertEqual(try XCTUnwrap(media.resources[fixture.id]?.url).lastPathComponent, expected)
        }
    }

    private func downloadItem(name: String?, type: String?) -> BoxItem {
        BoxItem(id: "filename", bossID: "boss", bossName: "Boss", kind: .file,
                text: name, hasMedia: true, mediaType: type, createdAt: "2026-01-01T00:00:00Z")
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

private actor FilenameBoxAPI: BoxServing {
    let data: Data

    init(data: Data) { self.data = data }

    func boxItems(filters: BoxFilters, limit: Int, cursor: String?) async throws -> BoxPage {
        BoxPage(items: [])
    }

    func downloadBoxMedia(id: String, to destination: URL) async throws {
        try data.write(to: destination)
    }

    func deleteBoxItem(id: String, purge: Bool) async throws {}
}
