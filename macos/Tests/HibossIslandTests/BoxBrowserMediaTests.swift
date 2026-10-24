// Verifies Box row media: the 4-download cap, thumbnail-first loads, one-time backfill without
// keeping the row's original, 405-only backfill shutdown, backoff retries and the caches.
// Dependencies: XCTest, AppKit, HibossKit and ScriptedBoxBrowser (no window classes).

import AppKit
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class BoxBrowserMediaTests: XCTestCase {
    func testDownloadsRunAtMostFourAtATime() async throws {
        let items = (0..<12).map { Self.image($0, thumbnail: $0.isMultiple(of: 2)) }
        let api = try await Self.api(storing: items.filter(\.hasThumbnail))
        await api.script(delay: 30_000_000)
        let media = BoxBrowserMedia(apiProvider: { api }, backfill: BoxBackfillSession())
        await withTaskGroup(of: Void.self) { group in
            for item in items { group.addTask { await media.loadThumbnail(item) } }
            for item in items.prefix(4) { group.addTask { _ = await media.load(item) } }
        }
        let peak = await api.peak
        XCTAssertLessThanOrEqual(peak, 4)
        XCTAssertGreaterThan(peak, 1)
        XCTAssertTrue(items.allSatisfy { media.thumbnail($0.id) != nil })
    }

    func testStoredThumbnailLoadsFirstAndViewerStillUsesOriginal() async throws {
        let item = Self.image(1, thumbnail: true)
        let api = try await Self.api(storing: [item])
        let cache = cache()
        let media = BoxBrowserMedia(apiProvider: { api }, cache: cache)
        await media.loadThumbnail(item)
        XCTAssertNotNil(media.thumbnail(item.id))
        XCTAssertNil(media.files[item.id])
        await BoxBrowserMedia(apiProvider: { api }, cache: cache).loadThumbnail(item)
        _ = await media.load(item)
        let requests = await api.requests
        XCTAssertEqual(requests, ["thumb:image-1", "media:image-1"])
    }

    func testBackfillPutsBoundedJPEGOnceAndDropsTheRowOriginal() async throws {
        let api = ScriptedBoxBrowser(media: try Self.png(width: 1600, height: 900))
        let media = BoxBrowserMedia(apiProvider: { api }, backfill: BoxBackfillSession())
        let item = Self.image(2)
        await media.loadThumbnailAndBackfill(item)
        let image = try XCTUnwrap(media.thumbnail(item.id))
        XCTAssertEqual(max(image.size.width, image.size.height), 512)
        XCTAssertNil(media.files[item.id], "a row's original is deleted once its thumbnail exists")
        let stored = await api.storedThumbnails
        let put = try XCTUnwrap(stored[item.id])
        XCTAssertTrue(put.starts(with: [0xFF, 0xD8, 0xFF]))
        XCTAssertLessThanOrEqual(put.count, BoxThumbnailGenerator.maxBytes)
        media.remove(id: item.id)
        await media.loadThumbnail(item)
        let requests = await api.requests
        XCTAssertEqual(requests, ["media:image-2", "put:image-2", "media:image-2"])
    }

    func testBackfillReusesAndKeepsAViewerOriginal() async throws {
        let api = ScriptedBoxBrowser(media: try Self.png(width: 800, height: 600))
        let media = BoxBrowserMedia(apiProvider: { api }, backfill: BoxBackfillSession())
        let item = Self.image(3)
        let loaded = await media.load(item)
        let file = try XCTUnwrap(loaded)
        await media.loadThumbnailAndBackfill(item)
        XCTAssertNotNil(media.thumbnail(item.id))
        XCTAssertEqual(media.files[item.id], file)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let requests = await api.requests
        XCTAssertEqual(requests, ["media:image-3", "put:image-3"])
    }

    func testBackfillTurnsOffOnlyAfter405() async throws {
        for (status, expected) in [(404, ["put:image-4", "put:image-5"]), (405, ["put:image-4"])] {
            let api = ScriptedBoxBrowser(media: try Self.png(width: 800, height: 600))
            await api.script(putStatus: status)
            let media = BoxBrowserMedia(apiProvider: { api }, backfill: BoxBackfillSession())
            await media.loadThumbnailAndBackfill(Self.image(4))
            await media.loadThumbnailAndBackfill(Self.image(5))
            let puts = await api.requests.filter { $0.hasPrefix("put:") }
            XCTAssertEqual(puts, expected, "status \(status)")
            XCTAssertNotNil(media.thumbnail("image-5"))
        }
    }

    func testFailedThumbnailRetriesOnReappearanceAfterBackoffAndManually() async throws {
        let item = Self.image(6, thumbnail: true)
        let api = try await Self.api(storing: [item])
        await api.script(failures: 2)
        let clock = MediaClock()
        let media = BoxBrowserMedia(apiProvider: { api }, now: { clock.date })
        await media.loadThumbnail(item)
        XCTAssertNotNil(media.thumbnailErrors[item.id])
        await media.loadThumbnail(item)
        var count = await api.requests.count
        XCTAssertEqual(count, 1, "no retry inside the backoff window")
        clock.date += 1
        await media.loadThumbnail(item)
        XCTAssertNotNil(media.thumbnailErrors[item.id])
        await media.retryThumbnail(item)
        XCTAssertNotNil(media.thumbnail(item.id), "the manual retry skips the backoff")
        count = await api.requests.count
        XCTAssertEqual(count, 3)
    }

    func testActivationRetriesVisibleFailedRowsOnly() async throws {
        let shown = Self.image(7, thumbnail: true), hidden = Self.image(8, thumbnail: true)
        let api = try await Self.api(storing: [shown, hidden])
        await api.script(failures: 2)
        let clock = MediaClock()
        let media = BoxBrowserMedia(apiProvider: { api }, now: { clock.date })
        await media.loadThumbnail(hidden)
        let row = Task { await media.show(shown) }
        defer { row.cancel() }
        try await waitForCondition { media.thumbnailErrors[shown.id] != nil }
        clock.date += 1
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        try await waitForCondition(timeout: .milliseconds(500)) { media.thumbnail(shown.id) != nil }
        XCTAssertNil(media.thumbnail(hidden.id))
        let requests = await api.requests
        XCTAssertEqual(requests.filter { $0 == "thumb:image-8" }.count, 1)
    }

    func testVisibleFailedRowRecoversWhenItsBackoffEnds() async throws {
        let item = Self.image(9, thumbnail: true)
        let api = try await Self.api(storing: [item])
        await api.script(failures: 1)
        let media = BoxBrowserMedia(apiProvider: { api }, backfill: BoxBackfillSession())
        let row = Task { await media.show(item) }
        defer { row.cancel() }
        try await waitForCondition(timeout: .seconds(4)) { media.thumbnail(item.id) != nil }
        let requests = await api.requests
        XCTAssertEqual(requests, ["thumb:image-9", "thumb:image-9"])
    }

    func testDecodedImagesAreCostBoundedAndReloadFromDiskAfterEviction() async throws {
        let item = Self.image(10, thumbnail: true)
        let api = try await Self.api(storing: [item])
        let media = BoxBrowserMedia(apiProvider: { api }, cache: cache())
        XCTAssertEqual(media.images.costLimit, 96 * 1024 * 1024)
        await media.loadThumbnail(item)
        media.images.removeAll()
        XCTAssertNil(media.thumbnail(item.id))
        await media.loadThumbnail(item)
        XCTAssertNotNil(media.thumbnail(item.id))
        let requests = await api.requests
        XCTAssertEqual(requests, ["thumb:image-10"])
    }

    func testDiskCacheEvictsOnItemRemovalAndLeastRecentlyUsedOverCap() async throws {
        let clock = MediaClock()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = BoxThumbnailCache(directory: directory, capacity: 250, now: { clock.date })
        for id in ["a", "b"] {
            await cache.store(Data(repeating: 1, count: 100), for: id)
            clock.date += 1
        }
        _ = await cache.data(for: "a")
        clock.date += 1
        await cache.store(Data(repeating: 2, count: 100), for: "c")
        let a = await cache.data(for: "a"), b = await cache.data(for: "b"), c = await cache.data(for: "c")
        XCTAssertNotNil(a)
        XCTAssertNil(b)
        XCTAssertNotNil(c)
        let media = BoxBrowserMedia(apiProvider: { ScriptedBoxBrowser() }, cache: cache)
        media.remove(id: "a")
        let path = directory.appendingPathComponent("a.jpg").path
        try await waitForCondition { !FileManager.default.fileExists(atPath: path) }
    }

    private func cache() -> BoxThumbnailCache {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return BoxThumbnailCache(directory: directory, capacity: 1024 * 1024)
    }

    static func api(storing items: [BoxItem]) async throws -> ScriptedBoxBrowser {
        let api = ScriptedBoxBrowser(media: try png(width: 800, height: 600))
        let image = try XCTUnwrap(NSBitmapImageRep(data: BoxBrowserFixtures.imageData())?.cgImage)
        let jpeg = try XCTUnwrap(BoxThumbnailGenerator.jpeg(image))
        for item in items { await api.storeThumbnail(jpeg, for: item.id) }
        return api
    }

    static func png(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0, green: 0.45, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    static func image(_ index: Int, thumbnail: Bool = false) -> BoxItem {
        BoxItem(id: "image-\(index)", bossID: "boss", bossName: "Owner", kind: .image, hasMedia: true,
                mediaType: "image/png", createdAt: "2026-10-07T00:00:00Z", hasThumbnail: thumbnail)
    }
}

extension BoxBrowserMedia {
    /// Loads a row image, then waits for the backfill PUT that its job may have started.
    func loadThumbnailAndBackfill(_ item: BoxItem) async {
        await loadThumbnail(item)
        await uploads[item.id]?.task?.value
    }
}

final class MediaClock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
}
