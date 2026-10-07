// Exercises drop classification, byte limits and resumable per-item submissions.
// Exports BoxDropTests covering real pasteboard representations and file snapshots.
// Dependencies: XCTest, AppKit, HibossKit and the macOS Box drop model.

import AppKit
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class BoxDropTests: XCTestCase {
    func testWebURLsAndTextAreClassifiedWithoutFetching() throws {
        let payloads = try BoxDropPayload.load([
            .text(" https://example.com/path?q=1 "), .text("http://example.com"),
            .text("Read https://example.com later"), .text("hello\nworld")
        ])
        XCTAssertEqual(payloads.map(\.kind), [.link, .link, .text, .text])
        XCTAssertEqual(payloads[0].url, "https://example.com/path?q=1")
        XCTAssertEqual(payloads[3].text, "hello\nworld")
        XCTAssertTrue(payloads.allSatisfy { $0.upload == nil })
    }

    func testFileURLsClassifyImageVideoAndOtherFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = ["image.png", "video.mp4", "document.pdf"].map { directory.appendingPathComponent($0) }
        for url in urls { try Data([1, 2, 3]).write(to: url) }
        let payloads = try BoxDropPayload.load(urls.map(BoxDropInput.file))
        XCTAssertEqual(payloads.map(\.kind), [.image, .video, .file])
        XCTAssertEqual(payloads.map { $0.upload?.mediaType }, ["image/png", "video/mp4", "application/pdf"])
        try Data([9]).write(to: urls[0])
        XCTAssertEqual(payloads[0].upload?.data, Data([1, 2, 3]), "retry bytes are a snapshot")
    }

    func testPasteboardChoosesOneRepresentationPerThing() throws {
        let file = NSPasteboardItem()
        file.setString("file:///tmp/image.png", forType: .fileURL)
        file.setString("image.png", forType: .string)
        file.setData(Data([1]), forType: .png)
        guard case let .file(url) = try BoxDropInput.read(file) else { return XCTFail("Expected file") }
        XCTAssertEqual(url.path, "/tmp/image.png")
        let link = NSPasteboardItem()
        link.setString("https://example.com", forType: .URL)
        link.setString("Page title", forType: .string)
        guard case let .text(value) = try BoxDropInput.read(link) else { return XCTFail("Expected URL") }
        XCTAssertEqual(try BoxDropPayload.load([.text(value)])[0].kind, .link)
        let fileURL = NSPasteboardItem()
        fileURL.setString("file:///tmp/document.pdf", forType: .URL)
        guard case .file = try BoxDropInput.read(fileURL) else { return XCTFail("Expected file URL") }
    }

    func testRawImageAndPlainTextPasteboardsAreAccepted() throws {
        let image = NSPasteboardItem()
        image.setData(Data([1, 2]), forType: .tiff)
        image.setString("https://example.com/image", forType: .URL)
        let payload = try BoxDropPayload.load([BoxDropInput.read(image)])[0]
        XCTAssertEqual(payload.kind, .image)
        XCTAssertEqual(payload.upload?.mediaType, "image/tiff")
        let text = NSPasteboardItem()
        text.setString("A passage", forType: .string)
        XCTAssertEqual(try BoxDropPayload.load([BoxDropInput.read(text)])[0].text, "A passage")
        XCTAssertThrowsError(try BoxDropInput.read(NSPasteboardItem()))
    }

    func testBatchCountIsOneThroughFourAndEmptyTextIsRejected() throws {
        XCTAssertThrowsError(try BoxDropPayload.load([]))
        XCTAssertEqual(try BoxDropPayload.load(Array(repeating: .text("x"), count: 4)).count, 4)
        XCTAssertThrowsError(try BoxDropPayload.load(Array(repeating: .text("x"), count: 5)))
        XCTAssertThrowsError(try BoxDropPayload.load([.text(" \n ")]))
    }

    func testMediaLimitsAreInclusiveAndRejectEmptyFiles() throws {
        for kind in [BoxItem.Kind.image, .video, .file] {
            let limit = (kind == .image ? 10 : 50) * 1024 * 1024
            XCTAssertNoThrow(try BoxDropPayload.validateSize(limit, kind: kind))
            XCTAssertThrowsError(try BoxDropPayload.validateSize(limit + 1, kind: kind))
            XCTAssertThrowsError(try BoxDropPayload.validateSize(0, kind: kind))
        }
    }

    func testTextLimitCountsUTF8Bytes() throws {
        XCTAssertNoThrow(try BoxDropPayload.load([.text(String(repeating: "a", count: 16 * 1024))]))
        XCTAssertThrowsError(try BoxDropPayload.load([.text(String(repeating: "a", count: 16 * 1024 + 1))]))
        XCTAssertThrowsError(try BoxDropPayload.load([.text(String(repeating: "界", count: 6000))]))
    }

    func testOversizedBatchNeverInvokesUpload() async {
        var calls = 0
        let store = BoxDropStore { _, _ in calls += 1 }
        await store.prepare([.text("valid"), .image(Data(count: 10 * 1024 * 1024 + 1), "image/png")])
        await store.save()
        XCTAssertEqual(store.phase, .rejected)
        XCTAssertNotNil(store.error)
        XCTAssertEqual(calls, 0)
    }

    func testOversizedFileIsRejectedBeforeReadingOrUploading() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try FileHandle(forWritingTo: url)
        try file.truncate(atOffset: 50 * 1024 * 1024 + 1)
        try file.close()
        var calls = 0
        let store = BoxDropStore { _, _ in calls += 1 }
        await store.prepare([.file(url)])
        await store.save()
        XCTAssertEqual(store.phase, .rejected)
        XCTAssertEqual(calls, 0)
    }

    func testRetryKeepsNoteKeysAndSkipsSuccessfulItems() async {
        var requests: [(BoxUpload, String)] = []
        let store = BoxDropStore { item, key in
            requests.append((item, key))
            if requests.count == 2 { throw TestError.rejected }
        }
        await store.prepare([.text("first"), .text("second")])
        store.note = "Keep this note"
        let keys = store.keys
        await store.save()
        XCTAssertEqual(store.phase, .failed)
        XCTAssertEqual(store.completed, 1)
        XCTAssertEqual(store.note, "Keep this note")
        XCTAssertTrue(store.noteLocked)
        await store.save()
        XCTAssertEqual(store.phase, .saved)
        XCTAssertEqual(store.completed, 2)
        XCTAssertEqual(requests.map { $0.1 }, [keys[0], keys[1], keys[1]])
        XCTAssertEqual(Set(keys).count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.0.source == .macDrop && $0.0.note == "Keep this note" })
        await store.save()
        XCTAssertEqual(requests.count, 3, "Save after confirmation cannot duplicate items")
    }

    func testMediaRetryUsesSnapshotAndRemovesTemporaryFiles() async throws {
        let original = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: original) }
        try Data([1, 2, 3]).write(to: original)
        var files: [URL] = []
        let store = BoxDropStore { upload, _ in
            let media = try XCTUnwrap(upload.media)
            files.append(media.fileURL)
            XCTAssertEqual(media.contentType, "image/png")
            XCTAssertEqual(try Data(contentsOf: media.fileURL), Data([1, 2, 3]))
            if files.count == 1 { throw TestError.rejected }
        }
        await store.prepare([.file(original)])
        try Data([9]).write(to: original)
        await store.save()
        XCTAssertEqual(store.phase, .failed)
        XCTAssertEqual(files.count, 1)
        let first = try XCTUnwrap(files.first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        await store.save()
        XCTAssertEqual(store.phase, .saved)
        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    func testNoteLimitBlocksUploadAndAllowsCorrection() async {
        var calls = 0
        let store = BoxDropStore { _, _ in calls += 1 }
        await store.prepare([.text("reference")])
        store.note = String(repeating: "界", count: 6000)
        await store.save()
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(store.phase, .ready)
        XCTAssertFalse(store.noteLocked)
        store.note = "Short note"
        await store.save()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(store.phase, .saved)
    }
}
