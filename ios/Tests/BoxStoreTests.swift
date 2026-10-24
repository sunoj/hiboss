// Verifies Box pagination, cached failure states, deletion and offline media lifetimes.
// Exports BoxStoreTests; production stores are driven through the BoxServing boundary.
// Dependencies: XCTest, AVFoundation, HibossKit and HiBoss Box/demo types.

import AVFoundation
import HibossKit
import UIKit
import XCTest
@testable import HiBoss

@MainActor
final class BoxStoreTests: XCTestCase {
    func testConnectionChangeResetsBoxForEitherServerOrCredential() throws {
        let server = try XCTUnwrap(URL(string: "https://one.example"))
        let otherServer = try XCTUnwrap(URL(string: "https://two.example"))
        let first = ConnectionConfig(serverURL: server, bossToken: "fixture-one")
        let changedServer = ConnectionConfig(serverURL: otherServer, bossToken: first.bossToken)
        let changedToken = ConnectionConfig(serverURL: server, bossToken: "fixture-two")
        XCTAssertNotEqual(BoxStore.connectionIdentity(first), BoxStore.connectionIdentity(changedServer))
        XCTAssertNotEqual(BoxStore.connectionIdentity(first), BoxStore.connectionIdentity(changedToken))
        XCTAssertNotEqual(BoxStore.connectionIdentity(first), BoxStore.connectionIdentity(nil))
        XCTAssertEqual(BoxStore.connectionIdentity(first), BoxStore.connectionIdentity(first))
    }

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
        XCTAssertNil(store.deleteError)
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
        XCTAssertEqual(second.items.count, 6)
        XCTAssertNil(second.nextCursor)
        XCTAssertEqual(Set((first.items + second.items).map(\.id)).count, 26)
        let media = BoxMediaStore(api: api, cache: nil)
        for kind in [BoxItem.Kind.image, .video, .file] {
            let item = try XCTUnwrap(first.items.first(where: { $0.kind == kind }))
            await media.load(item)
            let url = try XCTUnwrap(media.resources[item.id]?.url)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            if kind == .file { XCTAssertEqual(url.lastPathComponent, "Reference.txt") }
            if kind != .file {
                await media.loadThumbnail(item)
                XCTAssertNotNil(media.thumbnail(item.id))
            }
            if kind == .video {
                let duration = try await AVURLAsset(url: url).load(.duration)
                XCTAssertGreaterThan(duration.seconds, 0)
            }
            media.remove(id: item.id)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
            if kind == .file {
                XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
            }
        }
        let item = try XCTUnwrap(first.items.first)
        try await api.deleteBoxItem(id: item.id, purge: false)
        let after = try await api.boxItems(filters: BoxFilters(), limit: 20, cursor: nil)
        XCTAssertFalse(after.items.contains { $0.id == item.id })
    }

    func testEditingAndClearingNotePreservesTheOtherDetailFields() async throws {
        let store = BoxStore(api: DemoBoxAPI())
        await store.refresh()
        let item = try XCTUnwrap(store.items.first(where: { $0.id == "demo-image" }))
        let saved = await store.saveNote("New note", for: item)
        XCTAssertTrue(saved)
        let updated = try XCTUnwrap(store.items.first(where: { $0.id == item.id }))
        XCTAssertEqual(updated.note, "New note")
        XCTAssertEqual(updated.tags, item.tags)
        XCTAssertEqual(updated.project, item.project)
        XCTAssertEqual(updated.createdAt, item.createdAt)
        let cleared = await store.saveNote("", for: updated)
        XCTAssertTrue(cleared)
        XCTAssertNil(store.items.first(where: { $0.id == item.id })?.note)
        XCTAssertFalse(store.isSavingNote)
    }

    func testFailedMediaDoesNotRetryOnNavigationAndExplicitRetryRestoresTheResource() async throws {
        let api = FailingBoxMediaAPI()
        let page = try await api.boxItems(filters: BoxFilters(), limit: 20, cursor: nil)
        let item = try XCTUnwrap(page.items.first(where: { $0.kind == .image }))
        let media = BoxMediaStore(api: api, cache: nil)
        await media.load(item)
        XCTAssertNotNil(media.errors[item.id])
        await media.load(item)
        let attempts = await api.attempts
        XCTAssertEqual(attempts, 1)
        XCTAssertNil(media.resources[item.id])
        await media.retry(item)
        XCTAssertNotNil(media.resources[item.id])
        XCTAssertNil(media.errors[item.id])
    }

    func testCopyUsesTextLinkImageAndOriginalFileContent() async throws {
        let api = DemoBoxAPI()
        let page = try await api.boxItems(filters: BoxFilters(), limit: 20, cursor: nil)
        let media = BoxMediaStore(api: api, cache: nil)
        for kind in BoxItem.Kind.allCases {
            let item = try XCTUnwrap(page.items.first(where: { $0.kind == kind }))
            await media.load(item)
            item.copyContent(media: media)
            switch kind {
            case .text, .link: XCTAssertEqual(UIPasteboard.general.string, item.url ?? item.text)
            case .image:
                let path = try XCTUnwrap(media.resources[item.id]?.url.path)
                XCTAssertEqual(UIPasteboard.general.image?.size, UIImage(contentsOfFile: path)?.size)
                XCTAssertNotNil(UIPasteboard.general.image)
            case .video, .file: XCTAssertEqual(UIPasteboard.general.url, media.resources[item.id]?.url)
            }
        }
    }

    func testVideoThumbnailFailureKeepsDownloadedFileAvailable() async throws {
        let api = FailingBoxMediaAPI(invalidVideo: true)
        let page = try await api.boxItems(filters: BoxFilters(), limit: 20, cursor: nil)
        let item = try XCTUnwrap(page.items.first { $0.kind == .video })
        let media = BoxMediaStore(api: api, cache: nil)
        await media.load(item)
        let resource = try XCTUnwrap(media.resources[item.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: resource.url.path))
        XCTAssertNil(media.errors[item.id])
        await media.loadThumbnail(item)
        XCTAssertNil(media.thumbnail(item.id))
        XCTAssertNotNil(media.thumbnailErrors[item.id])
        XCTAssertTrue(media.resources[item.id] === resource)
    }

    func testSelectionDownloadsSelectedPageBeforeOnlyImmediateNeighbours() async {
        let api = FailingBoxMediaAPI(invalidVideo: true)
        let items = (0..<7).map {
            BoxItem(id: "file-\($0)", bossID: "boss", bossName: "Owner", kind: .file,
                    text: "file-\($0).txt", hasMedia: true, mediaType: "text/plain",
                    createdAt: "2026-10-07T00:00:00Z")
        }
        let media = BoxMediaStore(api: api, cache: nil)
        await media.loadSelection(id: "file-3", items: items)
        let requests = await api.requests
        XCTAssertEqual(requests, ["file-3", "file-4", "file-2"])
        await media.loadSelection(id: "file-4", items: items)
        let movedRequests = await api.requests
        XCTAssertEqual(movedRequests, ["file-3", "file-4", "file-2", "file-5"])
    }

    func testVideoPlaybackRejectsUnsupportedBytesInsteadOfLoadingForever() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".webm")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("Unsupported video fixture".utf8).write(to: url)
        let playback = MediaVideoPlayback()
        await playback.load(url)
        XCTAssertEqual(playback.state, .unavailable)
        XCTAssertNil(playback.player.currentItem)
    }

    func testVideoPlaybackKeepsPlayerButReplacesChangedURL() async throws {
        let api = DemoBoxAPI()
        let first = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        let second = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        try await api.downloadBoxMedia(id: "demo-video", to: first)
        try await api.downloadBoxMedia(id: "demo-video", to: second)
        let playback = MediaVideoPlayback()
        let player = playback.player
        await playback.load(first)
        XCTAssertEqual(playback.state, .ready)
        await playback.load(second)
        XCTAssertTrue(playback.player === player)
        XCTAssertEqual((playback.player.currentItem?.asset as? AVURLAsset)?.url, second)
        XCTAssertEqual(playback.state, .ready)
        playback.setPlaying(false)
        XCTAssertEqual(playback.player.rate, 0)
    }
}

private actor FailingBoxMediaAPI: BoxServing {
    private let demo = DemoBoxAPI()
    private(set) var attempts = 0
    private(set) var requests: [String] = []
    private let invalidVideo: Bool

    init(invalidVideo: Bool = false) { self.invalidVideo = invalidVideo }

    func boxItems(filters: BoxFilters, limit: Int, cursor: String?) async throws -> BoxPage {
        try await demo.boxItems(filters: filters, limit: limit, cursor: cursor)
    }

    func downloadBoxMedia(id: String, to destination: URL) async throws {
        attempts += 1
        requests.append(id)
        if invalidVideo {
            try Data("Invalid video fixture".utf8).write(to: destination)
            return
        }
        if attempts == 1 { throw HibossAPIError.requestFailed(status: 503, message: "unavailable") }
        try await demo.downloadBoxMedia(id: id, to: destination)
    }

    func deleteBoxItem(id: String, purge: Bool) async throws {
        try await demo.deleteBoxItem(id: id, purge: purge)
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
