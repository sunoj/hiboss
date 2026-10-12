// Verifies account invalidation withdraws cached wall content and selected detail.
// Exercises held old-account reads through PanelsModel and PanelsStartupAPI.

import XCTest
@testable import HibossKit

@MainActor
final class PanelsIdentityTests: XCTestCase {
    func testEarlierRejectionDoesNotInvalidateANewPanelModel() {
        AccountAuthorization.shared.reject(HibossAPIError.requestFailed(status: 401, message: ""))
        defer { AccountAuthorization.shared.connect(nil) }
        let model = PanelsModel(demoMode: false, autoload: false)
        model.clockTask?.cancel()
        model.connectionDidChange()
        model.reconciliationTask?.cancel()
        XCTAssertFalse(model.authorizationRejected,
                       "A new model did not observe the previous account's rejection")
    }

    func testRejectedPanelModelRemainsBlockedUntilAccountReconnects() {
        let model = PanelsModel(demoMode: false, autoload: false)
        model.clockTask?.cancel()
        AccountAuthorization.shared.reject(HibossAPIError.requestFailed(status: 401, message: ""))
        model.connectionDidChange()
        model.reconciliationTask?.cancel()
        XCTAssertTrue(model.authorizationRejected)
        AccountAuthorization.shared.connect(nil)
        model.connectionDidChange()
        model.reconciliationTask?.cancel()
        XCTAssertFalse(model.authorizationRejected)
    }

    func testAccountChangeImmediatelyClearsContentAndRejectsOldRead() async throws {
        let api = PanelsStartupAPI()
        let model = PanelsModel(api: api, demoMode: false, autoload: false)
        model.clockTask?.cancel()
        let fixture = try XCTUnwrap(PanelFixtures.load().all.first)
        let tile = PanelTile(id: "old", fixture: fixture, store: PanelStore(fixture: fixture),
            producer: nil, agentID: nil, agentName: nil, sessionLabel: nil,
            definitionRevision: nil, order: 0)
        model.tiles = [tile]
        model.pendingQuestionnaires = [PendingQuestionnaire(requestId: "old-question", panelId: tile.id,
            requestRevision: 1, title: "Old account", blocking: true, expiresAt: nil, createdAt: "")]
        model.didLoadPanels = true
        model.didLoadQuestionnaires = true
        model.loadState = .loaded
        model.open(tile.id)
        let oldRead = Task { await model.load() }
        await api.waitForPanels()

        model.connectionDidChange()
        XCTAssertTrue(model.tiles.isEmpty, "No previous-account tile may render after invalidation")
        XCTAssertTrue(model.pendingQuestionnaires.isEmpty)
        XCTAssertNil(model.selectedTileID, "Invalidation must dismiss the open detail and editors")
        XCTAssertNil(model.selectedTile)
        XCTAssertFalse(model.didLoadPanels)
        XCTAssertFalse(model.didLoadQuestionnaires)
        XCTAssertTrue(model.isLoading, "The new account starts with first-load presentation")
        XCTAssertFalse(model.hasDisplayCoverage)
        model.reconciliationTask?.cancel()
        model.reconciliationTask = nil
        await api.releasePanels()
        await oldRead.value
        XCTAssertTrue(model.tiles.isEmpty)
        XCTAssertFalse(model.didLoadPanels, "A late old-account read must not end first load")
    }

    func testOldReadCannotFinishNewAccountsPendingRead() async {
        let api = PanelsStartupAPI()
        let model = PanelsModel(api: api, demoMode: false, autoload: false)
        model.clockTask?.cancel()
        let old = Task { await model.load() }
        await api.waitForPanels()
        for _ in 0..<100 { await Task.yield() }
        model.connectionDidChange()
        model.reconciliationTask?.cancel()
        model.reconciliationTask = nil
        await api.holdQuestions()
        let current = Task { await model.load() }
        await api.waitForQuestions()
        await api.releasePanels()
        await old.value
        XCTAssertTrue(model.isFetching, "Old-account completion cannot finish the new panel read")
        XCTAssertTrue(model.isLoadingQuestions)
        XCTAssertFalse(model.hasDisplayCoverage)
        await api.releaseQuestions()
        await current.value
        XCTAssertTrue(model.hasCompleteCoverage)
    }

    func testImmediateNewAccountLoadConsumesScheduledReconciliation() async {
        let api = PanelsStartupAPI()
        let model = PanelsModel(api: api, demoMode: false, autoload: false)
        model.clockTask?.cancel()
        let initial = Task { await model.load() }
        await api.waitForPanels()
        await api.releasePanels()
        await initial.value
        model.connectionDidChange()
        let scheduled = model.reconciliationTask
        await model.load()
        await scheduled?.value
        let reads = await api.panelReads
        XCTAssertEqual(reads, 2, "An immediate account load must consume its queued reconciliation")
        XCTAssertTrue(model.hasCompleteCoverage)
    }
}
