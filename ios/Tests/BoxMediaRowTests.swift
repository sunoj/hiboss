// Verifies the row load task: a visible row recovers after its backoff without reappearing,
// a row cancelled while queued or downloading frees its slot and loads again, and the
// foreground retry covers visible rows only. Dependencies: XCTest, HibossKit, BoxMediaTestDoubles.

import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class BoxMediaRowTests: XCTestCase {
    private typealias Fixture = BoxMediaFixture

    func testVisibleRowRecoversAfterItsBackoffWithoutReappearing() async {
        let api = ThumbnailBoxAPI(failures: 1)
        let media = Fixture.store(api)
        let item = Fixture.image(0, thumbnail: true)
        let row = Task { await media.showThumbnail(item) }
        defer { row.cancel() }
        let failed = await Fixture.eventually { media.thumbnailErrors[item.id] != nil }
        XCTAssertTrue(failed)
        let recovered = await Fixture.eventually(4) { media.thumbnail(item.id) != nil }
        XCTAssertTrue(recovered, "the row retries once its 1 s backoff ends")
        await row.value
        XCTAssertNil(media.visibleRows[item.id])
    }

    func testRowCancelledWhileQueuedFreesNothingAndLoadsWhenItReappears() async {
        let api = ThumbnailBoxAPI(delay: 300_000_000)
        let media = Fixture.store(api, concurrency: 1)
        let running = Fixture.image(1, thumbnail: true), queued = Fixture.image(2, thumbnail: true)
        let first = Task { await media.showThumbnail(running) }
        let started = await Fixture.eventually { media.thumbnailTasks[running.id] != nil }
        XCTAssertTrue(started)
        let second = Task { await media.showThumbnail(queued) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        second.cancel()
        await second.value
        let left = await Fixture.eventually { media.thumbnailTasks[queued.id] == nil }
        XCTAssertTrue(left, "the cancelled row leaves no task behind")
        XCTAssertNil(media.thumbnailErrors[queued.id])
        await first.value
        await assertLoads(queued, in: media)
        let requests = await api.requests
        XCTAssertEqual(requests, ["thumb:image-1", "thumb:image-2"], "the queued row never downloaded")
    }

    func testRowCancelledWhileDownloadingFreesItsSlotAndLoadsWhenItReappears() async {
        let api = ThumbnailBoxAPI(delay: 300_000_000)
        let media = Fixture.store(api, concurrency: 1)
        let item = Fixture.image(3, thumbnail: true)
        let row = Task { await media.showThumbnail(item) }
        let started = await Fixture.eventually { media.thumbnailTasks[item.id] != nil }
        XCTAssertTrue(started)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let downloading = await api.requests
        XCTAssertEqual(downloading, ["thumb:image-3"], "cancelled inside the 300 ms download")
        row.cancel()
        await row.value
        let left = await Fixture.eventually { media.thumbnailTasks[item.id] == nil }
        XCTAssertTrue(left)
        XCTAssertNil(media.thumbnailErrors[item.id], "a cancelled download is not a failure")
        await assertLoads(Fixture.image(4, thumbnail: true), in: media)
        await assertLoads(item, in: media)
    }

    func testForegroundRetryCoversVisibleRowsOnly() async {
        let api = ThumbnailBoxAPI(failures: 2)
        let clock = TestClock()
        let media = Fixture.store(api, now: { clock.date })
        let hidden = Fixture.image(5, thumbnail: true), visible = Fixture.image(6, thumbnail: true)
        await media.loadThumbnail(hidden)
        let row = Task { await media.showThumbnail(visible) }
        defer { row.cancel() }
        let failed = await Fixture.eventually { media.thumbnailErrors[visible.id] != nil }
        XCTAssertTrue(failed)
        clock.date += 1
        await media.retryFailedLoads()
        XCTAssertNotNil(media.thumbnail(visible.id))
        XCTAssertNil(media.thumbnail(hidden.id))
        let requests = await api.requests
        XCTAssertEqual(requests, ["thumb:image-5", "thumb:image-6", "thumb:image-6"])
        await media.loadThumbnail(hidden)
        XCTAssertNotNil(media.thumbnail(hidden.id), "a hidden row still retries when it reappears")
    }

    /// Shows the row and fails if it does not load within two seconds, e.g. behind a leaked slot.
    private func assertLoads(_ item: BoxItem, in media: BoxMediaStore,
                             file: StaticString = #filePath, line: UInt = #line) async {
        let row = Task { await media.showThumbnail(item) }
        defer { row.cancel() }
        let loaded = await Fixture.eventually(2) { media.thumbnail(item.id) != nil }
        XCTAssertTrue(loaded, "\(item.id) did not load", file: file, line: line)
    }
}
