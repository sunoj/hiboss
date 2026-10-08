// Verifies actual JPEG conversion and medium-preset export using local fixtures.
// Exports ShareMediaPreparerTests; oversized images cannot reach the upload path unchanged.
// Dependencies: XCTest, UIKit, HibossKit and the app's bundled demo video.

import HibossKit
import UIKit
import XCTest
@testable import HiBoss

final class ShareMediaPreparerTests: XCTestCase {
    func testOversizedImageIsReencodedAsJPEGWithinTheLimit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        var data = try XCTUnwrap(image.pngData())
        data.append(Data(repeating: 0, count: SharePolicy.imageBytes))
        let url = directory.appendingPathComponent("oversized.png")
        try data.write(to: url)
        let media = try await ShareMediaPreparer.prepare(
            BoxUpload.Media(fileURL: url, contentType: "image/png"), kind: .image)
        XCTAssertEqual(media.contentType, "image/jpeg")
        let output = try Data(contentsOf: media.fileURL)
        XCTAssertLessThanOrEqual(output.count, SharePolicy.imageBytes)
        XCTAssertNotNil(UIImage(data: output))
        XCTAssertEqual(try Data(contentsOf: url).count, data.count)
    }

    func testSmallImageIsUnchangedAndInvalidOversizedImageIsRefused() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("image.png")
        try Data([1]).write(to: url)
        let original = BoxUpload.Media(fileURL: url, contentType: "image/png")
        let prepared = try await ShareMediaPreparer.prepare(original, kind: .image)
        XCTAssertEqual(prepared.fileURL, url)
        try Data(repeating: 0, count: SharePolicy.imageBytes + 1).write(to: url)
        do {
            _ = try await ShareMediaPreparer.prepare(original, kind: .image)
            XCTFail("Undecodable oversized images must not upload")
        } catch { XCTAssertTrue(error is ShareError) }
    }

    func testFileRemainsUnchangedAndOversizedFileReportsFiftyMBLimit() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Data("original document".utf8)
        try data.write(to: url)
        let original = BoxUpload.Media(fileURL: url, contentType: "application/pdf")
        let prepared = try await ShareMediaPreparer.prepare(original, kind: .file)
        XCTAssertEqual(prepared.fileURL, url)
        XCTAssertEqual(prepared.contentType, "application/pdf")
        XCTAssertEqual(try Data(contentsOf: prepared.fileURL), data)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(SharePolicy.fileBytes + 1))
        try handle.close()
        do {
            _ = try await ShareMediaPreparer.prepare(original, kind: .file)
            XCTFail("Oversized files must be refused before upload")
        } catch let error as ShareError {
            guard case .fileTooLarge = error else { return XCTFail("Expected the file limit error") }
            XCTAssertTrue(error.localizedDescription.contains("50 MB"))
        }
    }

    func testVideoExportsToMP4EvenWhenAlreadyBelowTheLimit() async throws {
        let source = try XCTUnwrap(Bundle.main.url(forResource: "demo-box-clip", withExtension: "mp4"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("clip.mp4")
        try FileManager.default.copyItem(at: source, to: url)
        let prepared = try await ShareMediaPreparer.prepare(
            BoxUpload.Media(fileURL: url, contentType: "video/mp4"), kind: .video)
        XCTAssertNotEqual(prepared.fileURL, url)
        XCTAssertEqual(prepared.contentType, "video/mp4")
        let size = try prepared.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        XCTAssertGreaterThan(size, 0)
        XCTAssertLessThanOrEqual(size, SharePolicy.videoBytes)
    }
}
