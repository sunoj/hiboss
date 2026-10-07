// Verifies Box pagination, cached failure states, deletion and offline media lifetimes.
// Exports BoxStoreTests; production stores are driven through the BoxServing boundary.
// Dependencies: XCTest, AVFoundation, HibossKit and HiBoss Box/demo types.

import AVFoundation
import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class BoxStoreTests: XCTestCase {
    func testPagesKeepOpaqueCursorDeduplicateAndRetainRowsOnRefreshFailure() async {
        let api = BoxStateAPI()
        let store = BoxStore(api: api)
        await store.refresh()
        XCTAssertEqual(store.items.map(\.id), ["first"])
        XCTAssertEqual(store.nextCursor, "opaque-page")
        await store.loadMore()
        XCTAssertEqual(store.items.map(\.id), ["first", "second"])
        XCTAssertNil(store.nextCursor)
        let cursors = await api.cursors
        XCTAssertEqual(cursors, [nil, "opaque-page"])
        await api.failReads()
        await store.refresh()
        XCTAssertEqual(store.items.map(\.id), ["first", "second"])
        XCTAssertNotNil(store.error)
        XCTAssertTrue(store.didLoad)
        XCTAssertFalse(store.isRefreshing)
    }

    func testFailedPageRetainsCursorAndExplicitRetryLoadsIt() async {
        let api = BoxStateAPI()
        let store = BoxStore(api: api)
        await store.refresh()
        await api.failReads()
        await store.loadMore()
        XCTAssertEqual(store.items.map(\.id), ["first"])
        XCTAssertEqual(store.nextCursor, "opaque-page")
        XCTAssertNotNil(store.pageError)
        await api.allowReads()
        await store.retryPage()
        XCTAssertEqual(store.items.map(\.id), ["first", "second"])
        XCTAssertNil(store.pageError)
    }

    func testFailedDeleteKeepsItemAndSuccessfulDeleteCannotBeResurrectedByRead() async throws {
        let api = BoxStateAPI()
        let store = BoxStore(api: api)
        await store.refresh()
        let item = try XCTUnwrap(store.items.first)
        await store.delete(item)
        XCTAssertEqual(store.items, [item])
        XCTAssertNotNil(store.deleteError)
        await api.allowDelete()
        await store.delete(item)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.deleting.isEmpty)
        await store.refresh()
        XCTAssertTrue(store.items.isEmpty, "A stale read must not restore the deleted item")
        let purges = await api.purges
        XCTAssertEqual(purges, [false, false])
    }

    func testDemoPagesAndMediaWorkWithoutNetworkAndCleanUpDownloadedFiles() async throws {
        let api = DemoBoxAPI()
        let first = try await api.boxItems(filters: BoxFilters(), limit: 20, cursor: nil)
        let second = try await api.boxItems(filters: BoxFilters(), limit: 20, cursor: first.nextCursor)
        XCTAssertEqual(first.items.count, 20)
        XCTAssertEqual(second.items.count, 5)
        XCTAssertNil(second.nextCursor)
        XCTAssertEqual(Set((first.items + second.items).map(\.id)).count, 25)
        let media = BoxMediaStore(api: api)
        for kind in [BoxItem.Kind.image, .video, .file] {
            let item = try XCTUnwrap(first.items.first(where: { $0.kind == kind }))
            await media.load(item)
            let url = try XCTUnwrap(media.resources[item.id]?.url)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            if kind != .file { XCTAssertNotNil(media.resources[item.id]?.thumbnail) }
            if kind == .video {
                let duration = try await AVURLAsset(url: url).load(.duration)
                XCTAssertGreaterThan(duration.seconds, 0)
            }
            media.remove(id: item.id)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
        let item = try XCTUnwrap(first.items.first)
        try await api.deleteBoxItem(id: item.id, purge: false)
        let after = try await api.boxItems(filters: BoxFilters(), limit: 20, cursor: nil)
        XCTAssertFalse(after.items.contains { $0.id == item.id })
    }
}

private actor BoxStateAPI: BoxServing {
    private var failing = false
    private var deleteFails = true
    private(set) var cursors: [String?] = []
    private(set) var purges: [Bool] = []

    func failReads() { failing = true }
    func allowReads() { failing = false }
    func allowDelete() { deleteFails = false }

    func boxItems(filters _: BoxFilters, limit _: Int, cursor: String?) async throws -> BoxPage {
        cursors.append(cursor)
        if failing { throw HibossAPIError.requestFailed(status: 503, message: "unavailable") }
        let first = BoxItem(id: "first", bossID: "boss", bossName: "Owner", kind: .text,
                            text: "First", createdAt: "2026-10-07T00:00:00Z")
        let second = BoxItem(id: "second", bossID: "boss", bossName: "Owner", kind: .text,
                             text: "Second", createdAt: "2026-10-06T00:00:00Z")
        return cursor == nil
            ? BoxPage(items: [first], nextCursor: "opaque-page") : BoxPage(items: [first, second])
    }

    func downloadBoxMedia(id _: String, to _: URL) async throws {}

    func deleteBoxItem(id _: String, purge: Bool) async throws {
        purges.append(purge)
        if deleteFails { throw HibossAPIError.requestFailed(status: 503, message: "unavailable") }
    }
}
