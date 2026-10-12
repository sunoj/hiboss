// Checks the shared status state before and after the 300 ms delay.
// Extends StableRefreshTests with cancellation coverage for fast reads.
// Dependencies: XCTest, the production RefreshStatus, and task cancellation.

import XCTest
@testable import HibossIsland

extension StableRefreshTests {
    func testRefreshStatusWaits300MillisecondsAndCancelsForFastReads() async throws {
        let status = RefreshStatus()
        let started = ContinuousClock.now
        let slow = Task { await status.update(isRefreshing: true) }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(status.showsUpdating, "Status must remain quiet before 300 ms")
        await slow.value
        XCTAssertGreaterThanOrEqual(started.duration(to: .now), .milliseconds(300))
        XCTAssertTrue(status.showsUpdating)
        await status.update(isRefreshing: false)
        XCTAssertFalse(status.showsUpdating)
        let fast = Task { await status.update(isRefreshing: true) }
        try await Task.sleep(for: .milliseconds(100))
        fast.cancel()
        await status.update(isRefreshing: false)
        await fast.value
        XCTAssertFalse(status.showsUpdating, "A completed fast read must cancel its delayed status")
    }
}
