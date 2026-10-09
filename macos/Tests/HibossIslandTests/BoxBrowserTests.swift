// Exercises Box pagination, errors, superseding searches and agent provenance.
// Exports: BoxBrowserTests, including deletion and authenticated media cache flows.
// Dependencies: XCTest, HibossKit and synthetic BoxBrowserTestSupport fixtures.

import AppKit
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class BoxBrowserTests: XCTestCase {
    func testPagesAreNewestFirstAndDeduplicated() async {
        let old = BoxBrowserFixtures.item("old", createdAt: "2026-10-08T08:00:00Z")
        let new = BoxBrowserFixtures.item("new")
        let api = ScriptedBoxBrowser(pages: [BoxPage(items: [old, new], nextCursor: "opaque"),
            BoxPage(items: [old, old, BoxBrowserFixtures.item("older", createdAt: "2026-10-07T08:00:00Z")])])
        let store = BoxBrowserStore { api }
        await store.refresh()
        XCTAssertEqual(store.items.map(\.id), ["new", "old"])
        XCTAssertEqual(store.nextCursor, "opaque")
        await store.loadMore()
        XCTAssertEqual(store.items.map(\.id), ["new", "old", "older"])
        XCTAssertNil(store.nextCursor)
    }

    func testReadAndPageFailuresPreserveRowsAndCanRetry() async {
        let api = ScriptedBoxBrowser(pages: [
            BoxPage(items: [BoxBrowserFixtures.items[0]], nextCursor: "next"),
            BoxPage(items: [BoxBrowserFixtures.items[1]])])
        let store = BoxBrowserStore { api }
        await store.refresh()
        await api.setReadFailure(true)
        await store.loadMore()
        XCTAssertNotNil(store.pageError)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.nextCursor, "next")
        await api.setReadFailure(false)
        await store.loadMore()
        XCTAssertEqual(store.items.count, 2)
        XCTAssertNil(store.pageError)
        await api.setReadFailure(true)
        await store.refresh()
        XCTAssertNotNil(store.error)
        XCTAssertEqual(store.items.count, 2)
        XCTAssertFalse(store.isLoading)
    }

    func testMissingConnectionAndEmptyResultsAreExplicit() async {
        let disconnected = BoxBrowserStore { nil }
        await disconnected.refresh()
        XCTAssertTrue(disconnected.didLoad)
        XCTAssertNotNil(disconnected.error)
        let api = ScriptedBoxBrowser(pages: [BoxPage(items: [])])
        let store = BoxBrowserStore { api }
        await store.refresh()
        XCTAssertTrue(store.didLoad)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNil(store.error)
    }

    func testSupersededReadCannotOverwriteSearchOrConnectionReset() async throws {
        let api = ScriptedBoxBrowser()
        let store = BoxBrowserStore { api }
        await api.holdNextRead()
        let old = Task { await store.refresh() }
        await api.waitForHeldRead()
        XCTAssertTrue(store.isLoading)
        store.query = "layout"
        await store.refresh()
        let results = store.items
        await api.releaseRead(BoxPage(items: [BoxBrowserFixtures.item("stale")], nextCursor: "stale"))
        await old.value
        XCTAssertEqual(store.items, results)
        XCTAssertNil(store.nextCursor)
        await api.holdNextRead()
        let previousConnection = Task { await store.refresh() }
        await api.waitForHeldRead()
        store.reset()
        await api.releaseRead(BoxPage(items: results))
        await previousConnection.value
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(store.didLoad)
    }

    func testAgentDeletionFailureRetainsItemAndSuccessCannotBeReinserted() async {
        let api = ScriptedBoxBrowser()
        let store = BoxBrowserStore { api }
        await store.refresh()
        let item = BoxBrowserFixtures.items[0]
        XCTAssertFalse(item.author.isBoss)
        await api.setDeleteFailure(true)
        let failed = await store.delete(item)
        XCTAssertFalse(failed)
        XCTAssertTrue(store.items.contains(item))
        XCTAssertNotNil(store.actionError)
        await api.setDeleteFailure(false)
        let succeeded = await store.delete(item)
        XCTAssertTrue(succeeded)
        await store.refresh()
        XCTAssertFalse(store.items.contains(item))
        let deleted = await api.deleted
        XCTAssertEqual(deleted, [item.id])
    }

    func testProvenanceDistinguishesNamedUnnamedAndBossItems() {
        XCTAssertEqual(BoxBrowserFixtures.items[0].provenance, L("Added by \("Design Agent")"))
        XCTAssertEqual(BoxBrowserFixtures.items[2].provenance, L("Added by an agent"))
        XCTAssertNil(BoxBrowserFixtures.items[1].provenance)
        XCTAssertNil(BoxBrowserFixtures.item("boss", author: .boss).provenance)
        XCTAssertEqual(BoxBrowserFixtures.item("blank", author: .agent(id: "a", name: "  ")).provenance,
            L("Added by an agent"))
    }

    func testImageMediaDownloadsOnceCreatesThumbnailAndRemovesCache() async throws {
        let api = ScriptedBoxBrowser(media: BoxBrowserFixtures.imageData())
        let media = BoxBrowserMedia { api }
        let item = BoxBrowserFixtures.items[0]
        let downloaded = await media.load(item)
        let file = try XCTUnwrap(downloaded)
        XCTAssertEqual(file.lastPathComponent, "Navigation preview.png")
        XCTAssertNotNil(media.thumbnails[item.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let repeated = await media.load(item)
        XCTAssertEqual(repeated, file)
        let count = await api.downloads
        XCTAssertEqual(count, 1)
        media.remove(id: item.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertNil(media.thumbnails[item.id])
    }

    func testFilenameCannotEscapeTemporaryDirectoryAndMimeTypeProvidesExtension() async throws {
        let api = ScriptedBoxBrowser(media: Data("document".utf8))
        let media = BoxBrowserMedia { api }
        let fileItem = BoxBrowserFixtures.item("file", kind: .file, text: "../../review",
            hasMedia: true, mediaType: "application/pdf")
        let downloaded = await media.load(fileItem)
        let file = try XCTUnwrap(downloaded)
        XCTAssertEqual(file.lastPathComponent, "review.pdf")
        XCTAssertEqual(try Data(contentsOf: file), Data("document".utf8))
        media.reset()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testFractionalTimestampsSortByInstantAndImageDecodeFailureIsExplicit() async {
        let api = ScriptedBoxBrowser(pages: [BoxPage(items: [
            BoxBrowserFixtures.item("old", createdAt: "2026-10-09T08:30:00Z"),
            BoxBrowserFixtures.item("new", createdAt: "2026-10-09T08:30:00.500Z")
        ])], media: Data("invalid image".utf8))
        let store = BoxBrowserStore { api }
        await store.refresh()
        XCTAssertEqual(store.items.map(\.id), ["new", "old"])
        let media = BoxBrowserMedia { api }
        let result = await media.load(BoxBrowserFixtures.items[0])
        XCTAssertNil(result)
        XCTAssertNotNil(media.errors["image"])
        XCTAssertNil(media.files["image"])
    }
}
