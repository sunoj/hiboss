// Covers server-backed PanelsModel empty and recoverable failure states.
// Exports: PanelsModelTests and a stub PanelsServing implementation.
// Dependencies: XCTest, HibossKit panel contracts, and HibossIsland PanelsModel.

import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class PanelsModelTests: XCTestCase {
    func testEmptyServerResponseIsAnHonestEmptyState() async {
        let model = PanelsModel(api: StubPanelsService(), demoMode: false, autoload: false)

        await model.load()

        XCTAssertTrue(model.tiles.isEmpty)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.failureMessage)
    }

    func testServerFailureIsVisibleAndRecoverable() async {
        let model = PanelsModel(api: StubPanelsService(failure: .unavailable), demoMode: false, autoload: false)

        await model.load()

        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.failureMessage, "The panel service is unavailable.")
    }

    func testServerBackedTilesNeedAReceivingSubscriptionForLive() async throws {
        let model = PanelsModel(api: try StubPanelsService(populated: true), demoMode: false, autoload: false)

        await model.load()

        XCTAssertFalse(model.tiles.isEmpty, "the populated stub should produce a tile")
        let tile = try XCTUnwrap(model.tiles.first)
        XCTAssertEqual(tile.sourceLabel, "Build Agent · checkout/main")
        assertNotLive(model.freshness(for: tile))

        model.receive(.snapshot(PanelRelaySnapshot(
            panelID: tile.id, definitionRevision: 1, epoch: "epoch-1", sequence: 0,
            task: .object(["done": .number(4)])
        )), for: tile.id)
        if case .live = model.freshness(for: tile) {} else {
            XCTFail("a receiving subscription should claim live")
        }

        // A subscription that silently stops delivering must degrade on its own. Only the
        // revoked path was covered, and revocation is the rarer failure — a socket that
        // goes quiet keeps its badge unless age is what decides.
        let stalled = Date().addingTimeInterval(PanelRelayConnection.expectedInterval * 2)
        assertNotLive(model.freshness(for: tile, at: stalled))
        let abandoned = Date().addingTimeInterval(PanelRelayConnection.expectedInterval * 10)
        assertNotLive(model.freshness(for: tile, at: abandoned))

        model.receive(.subscriptionRevoked, for: tile.id)
        assertNotLive(model.freshness(for: tile))
    }

    func testPublishedValuesReachTheCardAfterAFetchedSnapshot() async throws {
        let model = PanelsModel(api: try StubPanelsService(populated: true), demoMode: false, autoload: false)
        await model.load()
        let tile = try XCTUnwrap(model.tiles.first)

        XCTAssertEqual(tile.fixture.summary?.headline?.displayValue(in: tile.store.state), "3")
        model.receive(.snapshot(PanelRelaySnapshot(panelID: tile.id, definitionRevision: 1, epoch: "epoch-2", sequence: 0, task: .object(["done": .number(4)]))), for: tile.id)
        XCTAssertEqual(tile.fixture.summary?.headline?.displayValue(in: tile.store.state), "4")
    }

    func testPanelWithoutSummaryFallsBackToItsFirstMetric() throws {
        let fixtures = try PanelFixtures.load()
        let metric = try XCTUnwrap(fixtures.all.first { $0.name == "metric-panel.json" })
        XCTAssertNil(metric.summary)
        XCTAssertEqual(metric.firstMetricHeadline?.label, "Completed tests")
    }

    private func assertNotLive(_ freshness: PanelFreshness, file: StaticString = #filePath, line: UInt = #line) {
        if case .live = freshness { XCTFail("a tile without a receiving subscription claimed live", file: file, line: line) }
    }
}

actor StubPanelsService: PanelsServing {
    enum Failure: Error, LocalizedError {
        case unavailable

        var errorDescription: String? { "The panel service is unavailable." }
    }

    let failure: Failure?
    let panels: [PanelMetadata]
    let detail: PanelDetail?

    init(failure: Failure? = nil) {
        self.failure = failure
        panels = []
        detail = nil
    }

    init(populated: Bool) throws {
        failure = nil
        let decoder = JSONDecoder()
        detail = try decoder.decode(PanelDetail.self, from: Data(Self.detailJSON.utf8))
        panels = try [decoder.decode(PanelListPage.self, from: Data(Self.listJSON.utf8))].flatMap(\.panels)
    }

    func fetchPanels() async throws -> [PanelMetadata] {
        if let failure { throw failure }
        return panels
    }

    func fetchPanel(_ panelID: String) async throws -> PanelDetail {
        guard let detail else { throw Failure.unavailable }
        return detail
    }

    private static let listJSON = """
    {"panels":[{"panelId":"panel_1","agentId":"agent_1","agentName":"Build Agent","targetBossId":"boss_1","taskKey":"task","sessionId":"session_1","sessionLabel":"checkout/main","title":"Nightly transfer","catalogId":"hiboss.panel","catalogVersion":1,"definitionRevision":1,"metadataVersion":1,"summary":{"stage":"Running","headline":{"path":"/task/done","label":"Done"}},"createdAt":"2026-09-07T12:00:00Z"}]}
    """

    private static let detailJSON = """
    {"panelId":"panel_1","agentId":"agent_1","agentName":"Build Agent","targetBossId":"boss_1","taskKey":"task","sessionId":"session_1","sessionLabel":"checkout/main","title":"Nightly transfer","catalogId":"hiboss.panel","catalogVersion":1,"definitionRevision":1,"metadataVersion":1,"summary":{"stage":"Running","headline":{"path":"/task/done","label":"Done"}},"createdAt":"2026-09-07T12:00:00Z","definition":{"definitionRevision":1,"protocolVersion":1,"catalogId":"hiboss.panel","catalogVersion":1,"spec":{"root":"main","elements":{"main":{"type":"Metric","props":{"label":"Done","value":{"$state":"/task/done"}},"children":[]}}},"stateSchema":{"type":"object","properties":{"task":{"type":"object","properties":{"done":{"type":"integer"}},"required":["done"],"additionalProperties":false}},"required":["task"],"additionalProperties":false},"initialState":{"task":{"done":3}},"createdAt":"2026-09-07T12:00:00Z"}}
    """
}
