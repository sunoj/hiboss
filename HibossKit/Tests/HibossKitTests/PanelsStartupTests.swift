// Verifies startup preserves current work and overlaps independent source reads.
// Exports PanelsStartupTests using held API calls and the relay's frame delivery seam.
// Dependencies: XCTest, PanelsModel, PanelRelayConnection, and PanelsStartupAPI.

import XCTest
@testable import HibossKit

@MainActor
final class PanelsStartupTests: XCTestCase {
    func testQuestionnairesStartWhilePanelListIsHeld() async {
        let api = PanelsStartupAPI()
        let model = makeModel(api)
        let load = Task { await model.load() }
        await api.waitForPanels()
        for _ in 0..<100 { await Task.yield() }
        let reads = await api.questionReads
        XCTAssertEqual(reads, 1, "Questionnaires must not wait for panel metadata or details")
        await api.releasePanels()
        await load.value
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertTrue(model.hasCompleteQuestionnaires)
    }

    func testWallAcknowledgementPreservesInFlightPanelResults() async throws {
        let api = PanelsStartupAPI()
        let model = makeModel(api)
        model.wallConnection = try connection()
        let load = Task { await model.load() }
        await api.waitForPanels()
        let generation = model.questionnaireGeneration
        model.wallConnectivityChanged(true)
        XCTAssertEqual(model.questionnaireGeneration, generation)
        XCTAssertFalse(model.needsReconcile)
        XCTAssertNil(model.reconciliationTask)
        await api.releasePanels()
        await load.value
        await model.reconciliationTask?.value
        XCTAssertEqual(model.loadState, .loaded)
        let reads = await api.panelReads
        XCTAssertEqual(reads, 2, "Only the list is rechecked across wall readiness")
    }

    func testAcknowledgementRecheckRetainsStoreAndLiveCoverage() async throws {
        let api = PanelsStartupAPI()
        let model = makeModel(api)
        let fixture = try XCTUnwrap(PanelFixtures.load().all.first)
        let tile = PanelTile(id: "tile", fixture: fixture, store: PanelStore(fixture: fixture),
                             producer: nil, agentID: "agent", agentName: nil, sessionLabel: nil,
                             definitionRevision: 1, order: 0)
        model.tiles = [tile]
        model.receive(.snapshot(PanelRelaySnapshot(panelID: tile.id, definitionRevision: 1,
            epoch: "epoch", sequence: 0, task: .object([:]))), for: tile.id)
        let metadata = PanelMetadata(
            serverTime: 0, lifecycle: .running, preference: .automatic, finalSnapshot: nil,
            supersedesPanelId: nil, panelId: tile.id, agentId: "agent", agentName: nil,
            targetBossId: "boss", taskKey: "task", sessionId: "session", sessionLabel: nil,
            title: "Test", catalogId: "hiboss.panel", catalogVersion: 1, definitionRevision: 1,
            metadataVersion: 1, summary: .object([:]), createdAt: "2026-10-11T00:00:00Z")
        await api.setPanels([metadata])
        model.wallConnection = try connection()
        let load = Task { await model.load() }
        await api.waitForPanels()
        model.wallConnectivityChanged(true)
        await api.releasePanels()
        await load.value
        let installed = try XCTUnwrap(model.tiles.first)
        XCTAssertTrue(installed.store === tile.store)
        XCTAssertTrue(model.hasPanelCoverage(for: installed))
        XCTAssertEqual(model.loadState, .loaded, "Unchanged revisions must not refetch details/checkpoints")
        let reads = await api.panelReads
        XCTAssertEqual(reads, 2)
    }

    func testOverlappingForegroundLoadDoesNotSupersedeLaunch() async {
        let api = PanelsStartupAPI()
        let model = makeModel(api)
        let load = Task { await model.load() }
        await api.waitForPanels()
        let generation = model.questionnaireGeneration
        await model.load()
        XCTAssertEqual(model.questionnaireGeneration, generation)
        await api.releasePanels()
        await load.value
        await model.reconciliationTask?.value
        let reads = await api.panelReads
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertTrue(model.hasCompleteQuestionnaires)
    }

    func testFirstWallFrameOnlyAcknowledgesAndLaterFrameInvalidates() throws {
        var acknowledgements = 0
        var changes = 0
        let relay = try connection(onFrame: { _ in changes += 1 },
                                   onConnected: { acknowledgements += 1 })
        var acknowledged = false
        relay.deliver(.wallChanged, wallAcknowledged: &acknowledged)
        XCTAssertEqual(acknowledgements, 1)
        XCTAssertEqual(changes, 0)
        relay.deliver(.wallChanged, wallAcknowledged: &acknowledged)
        XCTAssertEqual(acknowledgements, 1)
        XCTAssertEqual(changes, 1, "Real changes must still reconcile")
    }

    func testLateAcknowledgementRechecksPanelsAfterJoinedQuestionnaires() async throws {
        let api = PanelsStartupAPI()
        await api.holdQuestions()
        let model = makeModel(api)
        model.wallConnection = try connection()
        let load = Task { await model.load() }
        await api.waitForPanels()
        await api.waitForQuestions()
        await api.releasePanels()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertTrue(model.tiles.isEmpty)
        let metadata = PanelMetadata(
            serverTime: 0, lifecycle: .running, preference: .automatic, finalSnapshot: nil,
            supersedesPanelId: nil, panelId: "new", agentId: "agent", agentName: nil,
            targetBossId: "boss", taskKey: "task", sessionId: "session", sessionLabel: nil,
            title: "New panel", catalogId: "hiboss.panel", catalogVersion: 1, definitionRevision: 1,
            metadataVersion: 1, summary: .object([:]), createdAt: "2026-10-11T00:00:00Z")
        await api.setPanels([metadata])
        model.wallConnectivityChanged(true)
        await api.releaseQuestions()
        await load.value
        XCTAssertEqual(model.tiles.map(\.id), ["new"], "Ack must revalidate the already-finished list")
        let reads = await api.panelReads
        XCTAssertEqual(reads, 2)
        XCTAssertFalse(model.tiles.allSatisfy { model.hasPanelCoverage(for: $0) },
                       "The discovered running panel still needs a received relay snapshot")
    }

    private func makeModel(_ api: PanelsStartupAPI) -> PanelsModel {
        let model = PanelsModel(api: api, demoMode: false, autoload: false)
        model.clockTask?.cancel()
        return model
    }

    private func connection(onFrame: @escaping (PanelRelayFrame) -> Void = { _ in },
                            onConnected: @escaping () -> Void = {}) throws -> PanelRelayConnection {
        let url = try XCTUnwrap(URL(string: "https://example.invalid"))
        return PanelRelayConnection(config: ConnectionConfig(serverURL: url, bossToken: "test"),
                                    panelID: "wall", isWall: true, onFrame: onFrame,
                                    onDisconnect: {}, onWallConnected: onConnected)
    }
}
