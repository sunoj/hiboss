// Verifies Box row media: the 4-download cap, thumbnail-first loads, one-time backfill, backoff
// retries on reappearance and foreground, and the disk cache's removal and LRU eviction.
// Dependencies: XCTest, HibossKit, UIKit and the HiBoss Box media store (fake BoxThumbnailServing).

import HibossKit
import UIKit
import XCTest
@testable import HiBoss

@MainActor
final class BoxMediaStoreTests: XCTestCase {
    func testDownloadsRunAtMostFourAtATime() async {
        let api = ThumbnailBoxAPI()
        let media = BoxMediaStore(api: api, cache: nil)
        let items = (0..<12).map { Self.image($0, thumbnail: $0.isMultiple(of: 2)) }
        await withTaskGroup(of: Void.self) { group in
            for item in items { group.addTask { await media.loadThumbnail(item) } }
            for item in items.prefix(4) { group.addTask { await media.load(item) } }
        }
        let peak = await api.peak
        XCTAssertLessThanOrEqual(peak, 4)
        XCTAssertGreaterThan(peak, 1)
        XCTAssertEqual(media.thumbnails.count, 12)
    }

    func testFailedLoadRetriesWhenRequestedAgainAfterBackoff() async throws {
        let api = ThumbnailBoxAPI(failures: 1)
        let media = BoxMediaStore(api: api, cache: nil)
        await media.load(Self.image(0))
        XCTAssertNotNil(media.errors["image-0"])
        try await Task.sleep(nanoseconds: 1_100_000_000)
        await media.load(Self.image(0))
        let attempts = await api.requests.count
        XCTAssertEqual(attempts, 2)
        XCTAssertNotNil(media.resources["image-0"])
    }

    func testStoredThumbnailLoadsFirstAndViewerStillUsesOriginal() async throws {
        let api = ThumbnailBoxAPI()
        let cache = cache()
        let item = Self.image(1, thumbnail: true)
        let media = BoxMediaStore(api: api, cache: cache)
        await media.loadThumbnail(item)
        XCTAssertNotNil(media.thumbnails[item.id])
        XCTAssertNil(media.resources[item.id])
        await BoxMediaStore(api: api, cache: cache).loadThumbnail(item)
        await media.load(item)
        let requests = await api.requests
        XCTAssertEqual(requests, ["thumb:image-1", "media:image-1"])
    }

    func testBackfillShowsDownsampledImageAndPutsBoundedJPEGOnce() async throws {
        let api = ThumbnailBoxAPI(putStatus: 500)
        let media = BoxMediaStore(api: api, cache: nil)
        let item = Self.image(2)
        await media.loadThumbnail(item)
        let image = try XCTUnwrap(media.thumbnails[item.id])
        XCTAssertEqual(max(image.size.width, image.size.height) * image.scale, 512)
        media.remove(id: item.id)
        await media.loadThumbnail(item)
        let requests = await api.requests
        XCTAssertEqual(requests, ["media:image-2", "put:image-2", "media:image-2"])
        let puts = await api.puts
        let put = try XCTUnwrap(puts.first)
        XCTAssertTrue(put.starts(with: [0xFF, 0xD8, 0xFF]))
        XCTAssertLessThanOrEqual(put.count, BoxThumbnailGenerator.maxBytes)
    }

    func testBackfillTurnsOffForTheSessionAfter404Or405() async {
        for status in [404, 405] {
            let api = ThumbnailBoxAPI(putStatus: status)
            let media = BoxMediaStore(api: api, cache: nil)
            await media.loadThumbnail(Self.image(3))
            await media.loadThumbnail(Self.image(4))
            let requests = await api.requests
            XCTAssertEqual(requests, ["media:image-3", "put:image-3", "media:image-4"])
            XCTAssertNotNil(media.thumbnails["image-4"])
        }
    }

    func testFailedThumbnailRetriesOnReappearanceAndForegroundWithBackoff() async {
        let api = ThumbnailBoxAPI(failures: 2)
        let clock = TestClock()
        let media = BoxMediaStore(api: api, cache: nil, now: { clock.date })
        let first = Self.image(5, thumbnail: true), second = Self.image(6, thumbnail: true)
        await media.loadThumbnail(first)
        await media.loadThumbnail(second)
        XCTAssertNotNil(media.thumbnailErrors[first.id])
        await media.loadThumbnail(first)
        await media.retryFailedLoads()
        var count = await api.requests.count
        XCTAssertEqual(count, 2, "no retry inside the backoff window")
        clock.date += 1
        await media.loadThumbnail(first)
        XCTAssertNotNil(media.thumbnails[first.id])
        XCTAssertNil(media.thumbnailErrors[first.id])
        await media.retryFailedLoads()
        XCTAssertNotNil(media.thumbnails[second.id])
        count = await api.requests.count
        XCTAssertEqual(count, 4)
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
        let media = BoxMediaStore(api: ThumbnailBoxAPI(), cache: cache)
        media.remove(id: "a")
        for _ in 0..<50 where FileManager.default.fileExists(atPath: directory.appendingPathComponent("a.jpg").path) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let removed = await cache.data(for: "a")
        XCTAssertNil(removed)
    }

    private func cache() -> BoxThumbnailCache {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return BoxThumbnailCache(directory: directory, capacity: 1024 * 1024)
    }

    private static func image(_ index: Int, thumbnail: Bool = false) -> BoxItem {
        BoxItem(id: "image-\(index)", bossID: "boss", bossName: "Owner", kind: .image, hasMedia: true,
                mediaType: "image/png", createdAt: "2026-10-07T00:00:00Z", hasThumbnail: thumbnail)
    }
}

private final class TestClock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
}

private actor ThumbnailBoxAPI: BoxThumbnailServing {
    static let original = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 500),
        format: { let format = UIGraphicsImageRendererFormat(); format.scale = 2; return format }())
        .image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1000, height: 500))
        }.pngData() ?? Data()
    private var failures: Int
    private let putStatus: Int?
    private var active = 0
    private(set) var peak = 0
    private(set) var requests: [String] = []
    private(set) var puts: [Data] = []

    init(failures: Int = 0, putStatus: Int? = nil) {
        self.failures = failures
        self.putStatus = putStatus
    }

    func boxItems(filters _: BoxFilters, limit _: Int, cursor _: String?) async throws -> BoxPage {
        BoxPage(items: [])
    }

    func downloadBoxMedia(id: String, to destination: URL) async throws {
        try await serve("media:\(id)")
        try Self.original.write(to: destination)
    }

    func downloadBoxThumbnail(id: String) async throws -> Data {
        try await serve("thumb:\(id)")
        return try XCTUnwrap(UIImage(data: Self.original)?.jpegData(compressionQuality: 0.5))
    }

    func uploadBoxThumbnail(id: String, data: Data, contentType _: String) async throws -> BoxItem {
        requests.append("put:\(id)")
        puts.append(data)
        if let putStatus { throw HibossAPIError.requestFailed(status: putStatus, message: "") }
        return BoxItem(id: id, bossID: "boss", bossName: "Owner", kind: .image, createdAt: "c",
                       hasThumbnail: true)
    }

    func deleteBoxItem(id _: String, purge _: Bool) async throws {}

    private func serve(_ request: String) async throws {
        requests.append(request)
        active += 1
        peak = max(peak, active)
        defer { active -= 1 }
        try await Task.sleep(nanoseconds: 30_000_000)
        if failures > 0 {
            failures -= 1
            throw HibossAPIError.requestFailed(status: 503, message: "unavailable")
        }
    }
}
