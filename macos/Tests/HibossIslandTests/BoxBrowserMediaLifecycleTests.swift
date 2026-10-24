// Verifies the Box row load lifecycle: a stable task id, a backfill PUT that survives its row,
// visible rows that recover after reset() and repeated failures, and app-session backfill rules.
// Dependencies: XCTest, HibossKit, BoxBrowserMediaTests fixtures and ScriptedBoxBrowser.

import AppKit
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class BoxBrowserMediaLifecycleTests: XCTestCase {
    private typealias Fixtures = BoxBrowserMediaTests

    func testTaskIDStaysWhenTheImageAppearsAndChangesOnEviction() async throws {
        let item = Fixtures.image(20, thumbnail: true)
        let api = try await Fixtures.api(storing: [item])
        let media = BoxBrowserMedia(apiProvider: { api }, images: BoxThumbnailMemory(),
                                    backfill: BoxBackfillSession())
        let before = media.thumbnailTaskID(item.id)
        await media.loadThumbnail(item)
        XCTAssertNotNil(media.thumbnail(item.id))
        XCTAssertEqual(media.thumbnailTaskID(item.id), before, "the image appearing must not restart the row")
        media.images.remove(item.id)
        try await waitForCondition { media.thumbnailTaskID(item.id) != before }
    }

    func testRowLeavingRightAfterTheImageAppearsKeepsItsBackfillPUT() async throws {
        let api = ScriptedBoxBrowser(media: try Fixtures.png(width: 800, height: 600))
        await api.script(putDelay: 200_000_000)
        let media = BoxBrowserMedia(apiProvider: { api }, backfill: BoxBackfillSession())
        let item = Fixtures.image(21)
        let row = Task { await media.show(item) }
        try await waitForCondition { media.thumbnail(item.id) != nil }
        row.cancel()
        await row.value
        let again = Task { await media.show(item) }
        defer { again.cancel() }
        try await Task.sleep(for: .milliseconds(300))
        let stored = await api.storedThumbnails
        XCTAssertNotNil(stored[item.id], "the PUT completed although its row left")
        let puts = await api.requests.filter { $0.hasPrefix("put:") }
        XCTAssertEqual(puts, ["put:image-21"])
    }

    func testDiskCacheHitWithoutServerThumbnailStillBackfills() async throws {
        let api = ScriptedBoxBrowser(media: try Fixtures.png(width: 800, height: 600))
        let cache = cache()
        for id in ["image-22", "image-23"] { await cache.store(try Self.jpeg(), for: id) }
        let media = BoxBrowserMedia(apiProvider: { api }, cache: cache, backfill: BoxBackfillSession())
        await media.loadThumbnail(Fixtures.image(22))
        await media.loadThumbnail(Fixtures.image(23, thumbnail: true))
        XCTAssertNotNil(media.thumbnail("image-23"))
        let requests = await api.requests
        XCTAssertEqual(requests, ["put:image-22"], "only the item the server lacks is backfilled")
    }

    func testVisibleRowReloadsAfterResetDuringALoad() async throws {
        let item = Fixtures.image(24, thumbnail: true)
        let api = try await Fixtures.api(storing: [item])
        await api.script(delay: 200_000_000)
        let media = BoxBrowserMedia(apiProvider: { api }, backfill: BoxBackfillSession())
        let row = Task { await media.show(item) }
        defer { row.cancel() }
        try await waitForCondition { media.thumbnailTasks[item.id] != nil }
        media.reset()
        try await waitForCondition(timeout: .seconds(2)) { media.thumbnail(item.id) != nil }
        let requests = await api.requests
        XCTAssertEqual(requests, ["thumb:image-24", "thumb:image-24"])
    }

    func testVisibleRowRetriesEachFailureWhenItsBackoffEnds() async throws {
        let item = Fixtures.image(25, thumbnail: true)
        let api = try await Fixtures.api(storing: [item])
        await api.script(failures: 2)
        let media = BoxBrowserMedia(apiProvider: { api }, backfill: BoxBackfillSession())
        let row = Task { await media.show(item) }
        defer { row.cancel() }
        try await waitForCondition(timeout: .seconds(6)) { media.thumbnail(item.id) != nil }
        let requests = await api.requests
        XCTAssertEqual(requests, ["thumb:image-25", "thumb:image-25", "thumb:image-25"])
    }

    func testBackfillSessionRulesSpanStoresAndCapAttempts() async throws {
        let cases: [(status: Int, puts: [String])] = [
            (503, ["put:image-26", "put:image-26", "put:image-27", "put:image-27"]),
            (404, ["put:image-26", "put:image-27"]),
            (405, ["put:image-26"]),
        ]
        for entry in cases {
            let api = ScriptedBoxBrowser(media: try Fixtures.png(width: 800, height: 600))
            await api.script(putStatus: entry.status)
            let session = BoxBackfillSession()
            for id in [26, 27] {
                for _ in 0..<3 {
                    let media = BoxBrowserMedia(apiProvider: { api }, backfill: session)
                    await media.loadThumbnail(Fixtures.image(id))
                }
            }
            let puts = await api.requests.filter { $0.hasPrefix("put:") }
            XCTAssertEqual(puts, entry.puts, "status \(entry.status)")
        }
    }

    private func cache() -> BoxThumbnailCache {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return BoxThumbnailCache(directory: directory, capacity: 1024 * 1024)
    }

    private static func jpeg() throws -> Data {
        let image = try XCTUnwrap(NSBitmapImageRep(data: BoxBrowserFixtures.imageData())?.cgImage)
        return try XCTUnwrap(BoxThumbnailGenerator.jpeg(image))
    }
}
