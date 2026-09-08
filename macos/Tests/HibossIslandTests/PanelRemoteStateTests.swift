// Checks that a fetched panel's published state reaches the bindings the spec declares.
// Exports: PanelRemoteStateTests.
// Dependencies: XCTest, HibossKit PanelDetail, PanelFixture, PanelStore.

import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class PanelRemoteStateTests: XCTestCase {
    func testRemoteInitialStateReachesTheDeclaredBindings() throws {
        let json = """
        {"panelId":"panel_1","agentId":"a","targetBossId":"b","taskKey":"t","sessionId":"s",
        "title":"Bot","catalogId":"hiboss.panel","catalogVersion":1,"definitionRevision":1,
        "metadataVersion":1,"serverTime":1788828000000,"lifecycle":{"taskState":"running","mode":"run","expectedUpdateIntervalSeconds":15,"terminalAt":null,"dismissAt":null,"dismissalPolicy":null,"result":null},"preference":{"preferenceVersion":0,"placement":"automatic","seenTerminalVersion":null,"acknowledgedTerminalVersion":null},"finalSnapshot":null,"supersedesPanelId":null,"summary":{"stage":"Running"},"createdAt":"2026-09-07T12:00:00Z",
        "definition":{"definitionRevision":1,"protocolVersion":2,"catalogId":"hiboss.panel",
        "catalogVersion":1,"createdAt":"2026-09-07T12:00:00Z",
        "spec":{"root":"main","elements":{"main":{"type":"Metric","props":{"label":"Mark price",
        "value":{"$state":"/task/markPrice"}},"children":[]}}},
        "stateSchema":{"type":"object","properties":{},"additionalProperties":true},
        "initialState":{"task":{"markPrice":2463.8}}}}
        """
        let detail = try JSONDecoder().decode(PanelDetail.self, from: Data(json.utf8))
        let fixture = PanelFixture(remote: detail)
        let store = PanelStore(fixture: fixture)
        let resolved = panelValue(at: "/task/markPrice", in: store.state)
        XCTAssertEqual(resolved?.number, 2463.8, "a fetched panel's published state must reach its bindings")
    }

    func testAnAuthoritativeEmptyTaskIsInstalledWithoutASequenceZeroFallback() async throws {
        let model = PanelsModel(api: try StubPanelsService(populated: true), demoMode: false, autoload: false)
        await model.load()
        let tile = try XCTUnwrap(model.tiles.first)
        model.receive(.snapshot(PanelRelaySnapshot(panelID: tile.id, definitionRevision: 1, epoch: "e1", sequence: 0, task: .object([:]))), for: tile.id)
        XCTAssertEqual(panelValue(at: "/task", in: tile.store.state), .object([:]))
        if case .awaitingData = model.freshness(for: tile) {} else { XCTFail("No observation was received") }
    }
}
