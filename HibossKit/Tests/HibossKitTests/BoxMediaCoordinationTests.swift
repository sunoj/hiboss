// Verifies the shared download cap, cancellation cleanup and backfill session reset.
// Exports BoxMediaCoordinationTests; uses isolated actors and no network or disk state.
// Dependencies: XCTest and HibossKit Box media coordination.

import XCTest
@testable import HibossKit

@MainActor
final class BoxMediaCoordinationTests: XCTestCase {
    func testConcurrentDownloadsRespectTheSharedLimit() async throws {
        let limiter = BoxMediaLimiter(limit: 2)
        let meter = DownloadMeter()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask { try await limiter.run { try await meter.load() } }
            }
            try await group.waitForAll()
        }
        let peak = await meter.peak
        XCTAssertGreaterThan(peak, 0)
        XCTAssertLessThanOrEqual(peak, 2)
    }

    func testCanceledDownloadReleasesItsSlotWithoutRunning() async throws {
        let limiter = BoxMediaLimiter(limit: 1)
        let canceled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await limiter.run {
                XCTFail("Canceled work must not start")
                return 0
            }
        }
        do {
            _ = try await canceled.value
            XCTFail("Cancellation must be reported")
        } catch is CancellationError {}
        let finished = expectation(description: "Released slot accepts another download")
        let next = Task {
            defer { finished.fulfill() }
            return try await limiter.run { 42 }
        }
        await fulfillment(of: [finished], timeout: 2)
        next.cancel()
        let value = try await next.value
        XCTAssertEqual(value, 42)
    }

    func testBackfillResetRestoresDisabledAndSettledItems() {
        let session = BoxBackfillSession()
        session.succeeded("settled")
        session.failed("unsupported", error: HibossAPIError.requestFailed(status: 405, message: ""))
        XCTAssertFalse(session.begin("fresh"))
        session.reset()
        XCTAssertTrue(session.enabled)
        XCTAssertTrue(session.begin("settled"))
        XCTAssertTrue(session.begin("fresh"))
    }
}

private actor DownloadMeter {
    private var active = 0
    private(set) var peak = 0

    func load() async throws {
        active += 1
        peak = max(peak, active)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(1))
    }
}
