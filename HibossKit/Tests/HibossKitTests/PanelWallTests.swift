// Verifies signal-driven reconciliation, concurrent discovery, and live-store preservation.
// Exports PanelWallTests; dependencies: XCTest and an actor-backed PanelsServing fixture.

import XCTest
@testable import HibossKit

@MainActor
final class PanelWallTests: XCTestCase {
    func testSignalDiscoversPanelsWithoutDroppingLiveStoresSelectionOrDrafts() async throws {
        let service = try WallPanelsService()
        let model = PanelsModel(api: service, demoMode: false, autoload: false)
        await model.load()
        let tile = try XCTUnwrap(model.tiles.first)
        model.open(tile.id)
        tile.store.setString("unsent answer", at: "/form/answer")
        model.receive(.snapshot(PanelRelaySnapshot(panelID: tile.id, definitionRevision: 1, epoch: "live", sequence: 0,
            task: .object(["done": .number(42)]))), for: tile.id)
        let connection = PanelRelayConnection(config: try config(), panelID: tile.id, onFrame: { _ in }, onDisconnect: {})
        model.relayConnections[tile.id] = connection
        await service.setCount(3)
        let signal = try JSONDecoder().decode(PanelRelayFrame.self, from: Data(#"{"kind":"wall.changed"}"#.utf8))
        let started = Date()
        for _ in 0..<10 { model.receiveWall(signal) }
        await waitUntil { model.tiles.count == 3 }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        XCTAssertTrue(model.tiles.first?.store === tile.store)
        XCTAssertTrue(model.relayConnections[tile.id] === connection)
        XCTAssertEqual(model.selectedTileID, tile.id)
        XCTAssertTrue(model.liveSubscriptions.contains(tile.id))
        XCTAssertEqual(panelValue(at: "/form/answer", in: tile.store.state), .string("unsent answer"))
        XCTAssertEqual(panelValue(at: "/task/done", in: tile.store.state), .number(42))
        let counts = await service.counts()
        XCTAssertEqual(counts.lists, 2, "A burst of signals should coalesce")
        XCTAssertEqual(counts.details, 3, "Existing live tiles must not refetch detail or state")
        XCTAssertEqual(counts.states, 3)
        XCTAssertGreaterThanOrEqual(counts.concurrent, 4, "New tiles and their independent REST reads must overlap")
    }

    func testSignalDuringFetchReconcilesAgainInsteadOfBeingLost() async throws {
        let service = try WallPanelsService()
        let model = PanelsModel(api: service, demoMode: false, autoload: false)
        let loading = Task { await model.load() }
        await waitUntil { model.isFetching }
        // The service snapshots its list before suspending, so this change needs another load.
        while await service.counts().lists == 0 { await Task.yield() }
        await service.setCount(2)
        model.receiveWall(.wallChanged)
        await loading.value
        await waitUntil { model.tiles.count == 2 }
        let counts = await service.counts()
        XCTAssertEqual(counts.lists, 2)
        XCTAssertNil(model.failureMessage)
    }

    func testUnrelatedFramesDoNotTriggerWallReads() async throws {
        let service = try WallPanelsService()
        let model = PanelsModel(api: service, demoMode: false, autoload: false)
        model.receiveWall(.ignored)
        model.receiveWall(.metadataChanged)
        XCTAssertNil(model.reconciliationTask)
        let counts = await service.counts()
        XCTAssertEqual(counts.lists, 0)
    }

    private func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<150 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(predicate(), "Reconciliation did not finish within 1.5 seconds")
    }

    private func config() throws -> ConnectionConfig {
        try ConnectionConfig(serverURL: XCTUnwrap(URL(string: "https://test.local")), bossToken: "test-token")
    }
}

private actor WallPanelsService: PanelsServing {
    private let details: [PanelDetail]
    private var count = 1
    private var lists = 0
    private var detailReads = 0
    private var stateReads = 0
    private var active = 0
    private var maximum = 0

    init() throws {
        details = try (1...3).map { index in
            try JSONDecoder().decode(PanelDetail.self, from: Data(Self.detail.replacingOccurrences(of: "panel_1", with: "panel_\(index)").utf8))
        }
    }

    func setCount(_ count: Int) { self.count = count }
    func counts() -> (lists: Int, details: Int, states: Int, concurrent: Int) { (lists, detailReads, stateReads, maximum) }

    func fetchPanels() async throws -> [PanelMetadata] {
        lists += 1
        let result = details.prefix(count).map(\.metadata)
        try await Task.sleep(for: .milliseconds(30))
        return result
    }

    func fetchPanel(_ panelID: String) async throws -> PanelDetail {
        detailReads += 1
        try await trackRead()
        return try XCTUnwrap(details.first { $0.metadata.panelId == panelID })
    }

    func fetchPanelState(_ panelID: String) async throws -> PanelRelaySnapshot {
        stateReads += 1
        try await trackRead()
        return PanelRelaySnapshot(panelID: panelID, definitionRevision: 1, epoch: nil, sequence: 0, task: .object(["done": .number(3)]))
    }

    private func trackRead() async throws {
        active += 1
        maximum = max(maximum, active)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(30))
    }

    func updatePanelPreference(_ panelID: String, command: PanelPreferenceCommand) async throws -> PanelPreference {
        throw HibossAPIError.invalidResponse
    }

    private static let detail = #"""
    {"panelId":"panel_1","agentId":"agent_1","targetBossId":"boss_1","taskKey":"task","sessionId":"session_1","title":"Build","catalogId":"hiboss.panel","catalogVersion":1,"definitionRevision":1,"metadataVersion":1,"serverTime":1788828000000,"lifecycle":{"taskState":"running","mode":"run","expectedUpdateIntervalSeconds":15,"terminalAt":null,"dismissAt":null,"dismissalPolicy":null,"result":null},"preference":{"preferenceVersion":0,"placement":"automatic","seenTerminalVersion":null,"acknowledgedTerminalVersion":null},"finalSnapshot":null,"supersedesPanelId":null,"summary":{},"createdAt":"2026-09-07T12:00:00Z","definition":{"definitionRevision":1,"protocolVersion":2,"catalogId":"hiboss.panel","catalogVersion":1,"spec":{"root":"main","elements":{"main":{"type":"Metric","props":{"label":"Done","value":{"$state":"/task/done"}},"children":[]}}},"stateSchema":{"type":"object"},"initialState":{"task":{"done":3},"form":{"answer":""}},"createdAt":"2026-09-07T12:00:00Z"}}
    """#
}
