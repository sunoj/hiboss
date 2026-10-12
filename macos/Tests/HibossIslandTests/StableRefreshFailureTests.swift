// Verifies known failures cannot become all-clear during another read or retry.
// Extends StableRefreshTests using production stores and deterministic held reads.
// Dependencies: XCTest, Combine, HibossKit, and StableReadAPI.

import Combine
import XCTest
@testable import HibossKit
@testable import HibossIsland

extension StableRefreshTests {
    func testHistoryRetryRetainsFailedHealthUntilSuccessfulResult() async throws {
        let api = try StableReadAPI()
        let flow = OptionFlowStore()
        let overview = OverviewStore()
        let inputs = CurrentValueSubject<RequiredInputState, Never>(
            RequiredInputState(ready: true, loaded: true))
        overview.bind(flow: flow, requiredInputs: inputs.eraseToAnyPublisher())
        flow.connect(api: api)
        defer { flow.disconnect() }
        try await waitForCondition { flow.historyState == .loaded }
        let panels = PanelsModel(api: api, demoMode: false, autoload: false)
        panels.clockTask?.cancel()
        await panels.load()
        await api.hold(.panels)
        let panelRefresh = Task { await panels.load() }
        await api.waitUntilHeld(.panels)
        overview.setQuestionnaireCoverage(panels.hasDisplayCoverage)
        await api.fail(.history)
        await flow.refreshHistory()
        let failedState = flow.historyState
        let failedHealth = overview.snapshot.today.health
        XCTAssertFalse(overview.snapshot.today.isAllClear)
        await api.succeed(.history)
        await api.hold(.history)
        let retry = Task { await flow.refreshHistory() }
        await api.waitUntilHeld(.history)
        XCTAssertTrue(flow.isRefreshingHistory)
        XCTAssertEqual(flow.historyState, failedState, "Retry must keep the named history failure")
        XCTAssertEqual(overview.snapshot.today.health, failedHealth,
            "Cached history cannot restore live health")
        XCTAssertFalse(overview.snapshot.today.isAllClear)
        await api.release(.history)
        await retry.value
        XCTAssertFalse(flow.isRefreshingHistory)
        XCTAssertEqual(flow.historyState, .loaded)
        XCTAssertTrue(overview.snapshot.today.isAllClear)
        await api.release(.panels)
        await panelRefresh.value
    }

    func testKnownPanelOrQuestionFailureSuppressesAllClearDuringOtherRead() async throws {
        for failedRead in [StableReadAPI.Read.panels, .questions] {
            let api = try StableReadAPI()
            let panels = PanelsModel(api: api, demoMode: false, autoload: false)
            panels.clockTask?.cancel()
            await panels.load()
            let heldRead: StableReadAPI.Read = failedRead == .panels ? .questions : .panels
            await api.hold(heldRead)
            await api.fail(failedRead)
            let refresh = Task { await panels.load() }
            await api.waitUntilHeld(heldRead)
            for _ in 0..<100 { await Task.yield() }
            let overview = OverviewStore()
            overview.update(history: [], live: nil, health: .live(checkedAt: .now),
                coverageComplete: panels.hasDisplayCoverage, requiredInputLoaded: true)
            XCTAssertFalse(panels.hasDisplayCoverage)
            XCTAssertFalse(overview.snapshot.today.isAllClear)
            XCTAssertNotNil(panels.questionnaireError ?? panels.failureMessage)
            await api.release(heldRead)
            await refresh.value
        }
    }
}
