// Verifies Box saving without presenting panels or creating windows.
// Dependencies: XCTest, authenticated media fixtures and injectable save destinations.

import Foundation
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class BoxSaveActionsTests: XCTestCase {
    func testFilenamePreservesOriginalAndUsesTitleWithMediaExtension() {
        let cache = URL(fileURLWithPath: "/cache/hashed-name.pdf")
        XCTAssertEqual(BoxBrowserActions.saveFilename(item(text: "original report.pdf"), source: cache),
            "original report.pdf")
        XCTAssertEqual(BoxBrowserActions.saveFilename(item(text: "Report"), source: cache), "Report.pdf")
        XCTAssertEqual(BoxBrowserActions.saveFilename(item(text: nil, note: "Meeting"), source: cache),
            "Meeting.pdf")
        XCTAssertEqual(BoxBrowserActions.saveFilename(item(text: "file", note: "Meeting"), source: cache),
            "Meeting.pdf")
        XCTAssertEqual(BoxBrowserActions.saveFilename(item(text: "folder/report.pdf"), source: cache),
            "report.pdf")
    }

    func testSaveCopiesAuthenticatedMediaAndReplacesConfirmedDestination() async throws {
        let api = ScriptedBoxBrowser(media: Data("new document".utf8))
        let media = BoxBrowserMedia { api }
        defer { media.reset() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("chosen.pdf")
        for existing in [false, true] {
            if existing { try Data("old document".utf8).write(to: destination) }
            try await BoxBrowserActions.save(item(text: "original.pdf"), media: media, panel: { name in
                XCTAssertEqual(name, "original.pdf")
                return destination
            }, fileManager: .default)
            XCTAssertEqual(try Data(contentsOf: destination), Data("new document".utf8))
            let source = try XCTUnwrap(media.files["save"])
            XCTAssertEqual(try Data(contentsOf: source), Data("new document".utf8))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["chosen.pdf"])
    }

    func testCancelDoesNotCopyOrRemoveSource() async throws {
        let api = ScriptedBoxBrowser(media: Data("document".utf8))
        let media = BoxBrowserMedia { api }
        defer { media.reset() }
        try await BoxBrowserActions.save(item(text: "original.pdf"), media: media, panel: { _ in nil })
        let source = try XCTUnwrap(media.files["save"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: source.deletingLastPathComponent().path),
            ["original.pdf"])
        XCTAssertEqual(try Data(contentsOf: source), Data("document".utf8))
    }

    func testUnavailableMediaThrowsBeforeShowingPanel() async {
        let media = BoxBrowserMedia { nil }
        do {
            try await BoxBrowserActions.save(item(text: "report.pdf"), media: media, panel: { _ in
                XCTFail("Failed media must not show a panel")
                return nil
            })
            XCTFail("Missing media must fail")
        } catch { XCTAssertNotNil(error as? BoxBrowserError) }
    }

    func testCopyFailureIsThrownAndPreservesOriginal() async throws {
        let api = ScriptedBoxBrowser(media: Data("document".utf8))
        let media = BoxBrowserMedia { api }
        defer { media.reset() }
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("report.pdf")
        do {
            try await BoxBrowserActions.save(item(text: "report.pdf"), media: media, panel: { _ in missing })
            XCTFail("An invalid destination must fail")
        } catch { XCTAssertTrue(error is CocoaError) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(media.files["save"]).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

    func testSaveIsOnlyAvailableForMediaAndFollowsOpen() {
        for kind in BoxItem.Kind.allCases {
            for hasMedia in [false, true] {
                let value = BoxItem(id: "item", bossID: "boss", bossName: "Boss", kind: kind,
                    hasMedia: hasMedia, createdAt: "2026-10-29T00:00:00Z")
                let actions = BoxPaneAction.available(for: value)
                XCTAssertEqual(actions.contains(.saveTo), hasMedia)
                if hasMedia {
                    XCTAssertEqual(actions.firstIndex(of: .saveTo), actions.firstIndex(of: .open).map { $0 + 1 })
                }
            }
        }
    }

    private func item(text: String?, note: String? = nil) -> BoxItem {
        BoxItem(id: "save", bossID: "boss", bossName: "Boss", kind: .file,
            text: text, note: note, hasMedia: true, mediaType: "application/pdf",
            createdAt: "2026-10-29T00:00:00Z")
    }
}
