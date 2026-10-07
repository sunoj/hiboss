// Exercises real item-provider representations and cancellation between competing loads.
// Exports ShareAttachmentLoaderTests; an old canceled load cannot replace a newer result.
// Dependencies: XCTest, UIKit, UniformTypeIdentifiers and the HiBoss share core.

import HibossKit
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import HiBoss

@MainActor
final class ShareAttachmentLoaderTests: XCTestCase {
    func testLoadsPlainTextURLAndDataBackedImageRepresentations() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let text = NSItemProvider(item: NSString(string: "reference"),
            typeIdentifier: UTType.plainText.identifier)
        let link = NSItemProvider(item: try XCTUnwrap(NSURL(string: "https://example.com")),
            typeIdentifier: UTType.url.identifier)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let imageProvider = NSItemProvider(object: image)
        let loaded = try await ShareAttachmentLoader.load([text, link, imageProvider], directory: directory)
        XCTAssertEqual(loaded.map(\.kind), [.text, .link, .image])
        XCTAssertEqual(loaded[0].text, "reference")
        XCTAssertEqual(loaded[1].url, "https://example.com")
        let media = try XCTUnwrap(loaded[2].media)
        XCTAssertTrue(media.contentType.hasPrefix("image/"))
        XCTAssertNotNil(UIImage(contentsOfFile: media.fileURL.path))
    }

    func testCanceledLoadCannotOverwriteNewerReadyAttachments() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let requested = XCTestExpectation(description: "Older provider requested")
        let gate = ShareProviderGate(requested: requested)
        let old = NSItemProvider()
        old.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier,
            visibility: .all) { completion in
                Task { await gate.hold(completion) }
                return Progress(totalUnitCount: 1)
            }
        let model = ShareViewModel(api: DemoShareLoaderUpload())
        let oldLoad = Task { await model.load([old], directory: directory) }
        await fulfillment(of: [requested], timeout: 5)
        guard await gate.isReady else {
            oldLoad.cancel()
            return
        }
        oldLoad.cancel()
        let newer = NSItemProvider(item: NSString(string: "newer reference"),
            typeIdentifier: UTType.plainText.identifier)
        await model.load([newer], directory: directory)
        XCTAssertEqual(model.state, .ready)
        await gate.release()
        await oldLoad.value
        XCTAssertEqual(model.state, .ready)
        XCTAssertEqual(model.attachments.first?.text, "newer reference")
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor ShareProviderGate {
    private var completion: (@Sendable (Data?, (any Error)?) -> Void)?
    private let requested: XCTestExpectation

    init(requested: XCTestExpectation) { self.requested = requested }

    var isReady: Bool { completion != nil }

    func hold(_ completion: @escaping @Sendable (Data?, (any Error)?) -> Void) {
        self.completion = completion
        requested.fulfill()
    }

    func release() {
        completion?(Data("older reference".utf8), nil)
        completion = nil
    }
}

private struct DemoShareLoaderUpload: BoxUploading {
    func createBoxItem(
        _ upload: BoxUpload, idempotencyKey: String, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> BoxItem {
        throw URLError(.notConnectedToInternet)
    }
}
