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

    func testServerBackedTilesNeverClaimToBeLive() async throws {
        // The invariant this whole change rests on: there is no relay yet, so nothing
        // fetched over HTTP is entitled to a live badge. A wall of green would tell the
        // boss their agents are running when all it means is that a fetch succeeded.
        let model = PanelsModel(api: try StubPanelsService(populated: true), demoMode: false, autoload: false)

        await model.load()

        XCTAssertFalse(model.tiles.isEmpty, "the populated stub should produce a tile")
        for tile in model.tiles {
            switch model.freshness(for: tile) {
            case .fetched, .cachedFailure:
                continue
            case .live, .stale, .offline:
                XCTFail("a server-backed tile reported \(model.freshness(for: tile).title) instead of its fetch time")
            }
        }
    }
}

private actor StubPanelsService: PanelsServing {
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
    {"panels":[{"panelId":"panel_1","agentId":"agent_1","targetBossId":"boss_1","taskKey":"task","sessionId":"session_1","title":"Nightly transfer","catalogId":"hiboss.panel","catalogVersion":1,"definitionRevision":1,"metadataVersion":1,"summary":{"stage":"Running"},"createdAt":"2026-09-07T12:00:00Z"}]}
    """

    private static let detailJSON = """
    {"panelId":"panel_1","agentId":"agent_1","targetBossId":"boss_1","taskKey":"task","sessionId":"session_1","title":"Nightly transfer","catalogId":"hiboss.panel","catalogVersion":1,"definitionRevision":1,"metadataVersion":1,"summary":{"stage":"Running"},"createdAt":"2026-09-07T12:00:00Z","definition":{"definitionRevision":1,"protocolVersion":1,"catalogId":"hiboss.panel","catalogVersion":1,"spec":{"root":"main","elements":{"main":{"type":"Metric","props":{"label":"Done","value":{"$state":"/task/done"}},"children":[]}}},"stateSchema":{"type":"object","properties":{"task":{"type":"object","properties":{"done":{"type":"integer"}},"required":["done"],"additionalProperties":false}},"required":["task"],"additionalProperties":false},"initialState":{"task":{"done":3}},"createdAt":"2026-09-07T12:00:00Z"}}
    """
}
