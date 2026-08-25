// HomeStore tests for loading / error / loaded state transitions.
// Exports: HomeStoreTests covering refresh success, failure, and retention.
// Dependencies: XCTest, HiBoss app target, HibossKit HomeServing.

import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class HomeStoreTests: XCTestCase {
    func testRefreshTransitionsFromLoadingToLoaded() async {
        let api = ScriptedHomeAPI(result: .success(Self.sample))
        let store = HomeStore()
        XCTAssertTrue(store.isLoading)
        XCTAssertFalse(store.showsError)

        store.start(api: api)
        await store.refresh()

        XCTAssertFalse(store.isLoading)
        XCTAssertFalse(store.showsError)
        XCTAssertTrue(store.didLoad)
        XCTAssertEqual(store.dashboard?.boss.name, "Ming")
        XCTAssertNil(store.loadError)
    }

    func testFailedFirstFetchShowsErrorNotAllClear() async {
        let api = ScriptedHomeAPI(result: .failure(HibossAPIError.requestFailed(status: 500, message: "down")))
        let store = HomeStore()
        store.start(api: api)
        await store.refresh()

        XCTAssertTrue(store.showsError)
        XCTAssertNil(store.dashboard)
        XCTAssertEqual(store.loadError, "down")
        XCTAssertFalse(store.isLoading)
    }

    func testTransientFailureKeepsPreviousDashboard() async {
        let api = ScriptedHomeAPI(result: .success(Self.sample))
        let store = HomeStore()
        store.start(api: api)
        await store.refresh()
        XCTAssertEqual(store.dashboard?.boss.name, "Ming")

        api.result = .failure(HibossAPIError.requestFailed(status: 503, message: "busy"))
        await store.refresh()

        XCTAssertEqual(store.dashboard?.boss.name, "Ming")
        XCTAssertEqual(store.loadError, "busy")
        XCTAssertFalse(store.showsError)
    }

    func testStopClearsLoadedState() async {
        let api = ScriptedHomeAPI(result: .success(Self.sample))
        let store = HomeStore()
        store.start(api: api)
        await store.refresh()
        store.stop()

        XCTAssertNil(store.dashboard)
        XCTAssertFalse(store.didLoad)
        XCTAssertTrue(store.isLoading)
    }

    private static let sample = HomeDashboard(
        boss: HomeBoss(name: "Ming"),
        kpis: HomeKPIs(
            activeSessions: 1, workingSessions: 1,
            pendingDecisions: 0, blockingPending: 0, unread1h: 0
        ),
        activity: HomeActivity(
            days: [HomeActivityDay(date: "2026-08-01", posts: 1, decisions: 0, messages: 2)],
            delta: HomeActivityDelta(posts: nil, decisions: nil, messages: nil)
        )
    )
}

private final class ScriptedHomeAPI: HomeServing, @unchecked Sendable {
    var result: Result<HomeDashboard, Error>

    init(result: Result<HomeDashboard, Error>) {
        self.result = result
    }

    func fetchHome() async throws -> HomeDashboard {
        try result.get()
    }
}
