// Verifies Box row media: the 4-download cap, thumbnail-first loads, bounded backfill, the
// memory and disk caches, and that a backfill's original is deleted once the thumbnail exists.
// Dependencies: XCTest, HibossKit, UIKit and the HiBoss Box media store (BoxMediaTestDoubles).

import HibossKit
import UIKit
import XCTest
@testable import HiBoss

@MainActor
final class BoxMediaStoreTests: XCTestCase {
    private typealias Fixture = BoxMediaFixture

    func testDownloadsRunAtMostFourAtATime() async {
        let api = ThumbnailBoxAPI()
        let media = Fixture.store(api)
        let items = (0..<12).map { Fixture.image($0, thumbnail: $0.isMultiple(of: 2)) }
        await withTaskGroup(of: Void.self) { group in
            for item in items { group.addTask { await media.loadThumbnail(item) } }
            for item in items.prefix(4) { group.addTask { await media.load(item) } }
        }
        let peak = await api.peak
        XCTAssertLessThanOrEqual(peak, 4)
        XCTAssertGreaterThan(peak, 1)
        XCTAssertEqual(items.filter { media.thumbnail($0.id) != nil }.count, 12)
    }

    func testFailedLoadRetriesWhenRequestedAgainAfterBackoff() async throws {
        let api = ThumbnailBoxAPI(failures: 1)
        let media = Fixture.store(api)
        await media.load(Fixture.image(0))
        XCTAssertNotNil(media.errors["image-0"])
        try await Task.sleep(nanoseconds: 1_100_000_000)
        await media.load(Fixture.image(0))
        let attempts = await api.requests.count
        XCTAssertEqual(attempts, 2)
        XCTAssertNotNil(media.resources["image-0"])
    }

    func testStoredThumbnailLoadsFirstAndViewerStillUsesOriginal() async throws {
        let api = ThumbnailBoxAPI()
        let cache = cache()
        let item = Fixture.image(1, thumbnail: true)
        let media = Fixture.store(api, cache: cache)
        await media.loadThumbnail(item)
        XCTAssertNotNil(media.thumbnail(item.id))
        XCTAssertNil(media.resources[item.id])
        await Fixture.store(api, cache: cache).loadThumbnail(item)
        await media.load(item)
        let requests = await api.requests
        XCTAssertEqual(requests, ["thumb:image-1", "media:image-1"])
    }

    func testBackfillShowsDownsampledImageAndPutsBoundedJPEG() async throws {
        let api = ThumbnailBoxAPI()
        let media = Fixture.store(api)
        let item = Fixture.image(2)
        await media.loadThumbnail(item)
        let image = try XCTUnwrap(media.thumbnail(item.id))
        XCTAssertEqual(max(image.size.width, image.size.height) * image.scale, 512)
        let requests = await api.requests, puts = await api.puts
        XCTAssertEqual(requests, ["media:image-2", "put:image-2"])
        let put = try XCTUnwrap(puts.first)
        XCTAssertTrue(put.starts(with: [0xFF, 0xD8, 0xFF]))
        XCTAssertLessThanOrEqual(put.count, BoxThumbnailGenerator.maxBytes)
    }

    func testBackfillDeletesItsOriginalUnlessAViewerRequestedIt() async throws {
        let api = ThumbnailBoxAPI()
        let media = Fixture.store(api)
        await media.loadThumbnail(Fixture.image(3))
        XCTAssertNotNil(media.thumbnail("image-3"))
        XCTAssertNil(media.resources["image-3"])
        let backfilled = try await XCTUnwrapAsync(await api.destinations.first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backfilled.deletingLastPathComponent().path))
        let viewed = Fixture.image(4)
        await media.load(viewed)
        await media.loadThumbnail(viewed)
        let url = try XCTUnwrap(media.resources[viewed.id]?.url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let downloads = await api.requests.filter { $0 == "media:image-4" }
        XCTAssertEqual(downloads.count, 1)
    }

    func testBackfillTurnsOffForTheAppSessionOnlyOn405() async {
        let session = BoxBackfillSession()
        let gone = ThumbnailBoxAPI(putStatus: 404)
        await Fixture.store(gone, backfill: session).loadThumbnail(Fixture.image(5))
        await Fixture.store(gone, backfill: session).loadThumbnail(Fixture.image(6))
        var puts = await gone.requests.filter { $0.hasPrefix("put:") }
        XCTAssertEqual(puts, ["put:image-5", "put:image-6"], "a 404 skips only its own item")
        let old = ThumbnailBoxAPI(putStatus: 405)
        await Fixture.store(old, backfill: session).loadThumbnail(Fixture.image(7))
        let other = Fixture.store(old, backfill: session)
        await other.loadThumbnail(Fixture.image(8))
        puts = await old.requests.filter { $0.hasPrefix("put:") }
        XCTAssertEqual(puts, ["put:image-7"], "a 405 turns backfill off for every store")
        XCTAssertNotNil(other.thumbnail("image-8"))
    }

    func testTransientBackfillFailureRetriesOnceOnALaterLoad() async {
        let cache = cache(), session = BoxBackfillSession()
        let api = ThumbnailBoxAPI(putStatuses: [500])
        for _ in 0..<3 { await Fixture.store(api, cache: cache, backfill: session).loadThumbnail(Fixture.image(9)) }
        let requests = await api.requests
        XCTAssertEqual(requests, ["media:image-9", "put:image-9", "put:image-9"])
        let recovered = ThumbnailBoxAPI(putStatuses: [503, nil])
        let later = BoxBackfillSession()
        for _ in 0..<3 { await Fixture.store(recovered, cache: cache, backfill: later).loadThumbnail(Fixture.image(10)) }
        let puts = await recovered.requests.filter { $0.hasPrefix("put:") }
        XCTAssertEqual(puts.count, 2, "a successful retry settles the item")
    }

    func testRowImagesStayWithinTheMemoryCapAndClearOnMemoryWarning() async throws {
        let api = ThumbnailBoxAPI()
        let original = try XCTUnwrap(UIImage(data: ThumbnailBoxAPI.original))
        let bytes = Int(original.size.width * original.scale * original.size.height * original.scale) * 4
        let media = Fixture.store(api, cache: cache(), memory: BoxThumbnailMemory(costLimit: bytes * 3 / 2))
        let items = (11..<14).map { Fixture.image($0, thumbnail: true) }
        for item in items { await media.loadThumbnail(item) }
        XCTAssertLessThan(items.filter { media.thumbnail($0.id) != nil }.count, 3)
        let reported = await Fixture.eventually { media.thumbnailEpochs.values.reduce(0, +) > 0 }
        XCTAssertTrue(reported, "an eviction re-runs the visible row's task")
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertTrue(items.allSatisfy { media.thumbnail($0.id) == nil })
        for item in items { await media.loadThumbnail(item) }
        let requests = await api.requests
        XCTAssertEqual(requests.count, 3, "misses after a memory warning come from the disk cache")
    }

    func testCacheEvictsOnItemRemovalAndLeastRecentlyUsedOverCap() async throws {
        let clock = TestClock()
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
        let media = Fixture.store(ThumbnailBoxAPI(), cache: cache)
        media.remove(id: "a")
        for _ in 0..<50 where FileManager.default.fileExists(atPath: directory.appendingPathComponent("a.jpg").path) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let removed = await cache.data(for: "a")
        XCTAssertNil(removed)
    }

    func testTranslucentImageThumbnailIsFlattenedOntoWhiteOnIOS() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        try UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).pngData { context in
            UIColor.red.withAlphaComponent(0.5).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }.write(to: url)
        let data = try await XCTUnwrapAsync(await BoxThumbnailGenerator.thumbnail(for: url, kind: .image))
        let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertGreaterThan(pixel[0], 240, "\(pixel)")
        XCTAssertTrue((100...170).contains(pixel[1]) && (100...170).contains(pixel[2]), "\(pixel)")
    }

    private func XCTUnwrapAsync<T>(_ value: T?) async throws -> T { try XCTUnwrap(value) }

    private func cache() -> BoxThumbnailCache {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return BoxThumbnailCache(directory: directory, capacity: 64 * 1024 * 1024)
    }
}
