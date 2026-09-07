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
        "metadataVersion":1,"summary":{"stage":"Running"},"createdAt":"2026-09-07T12:00:00Z",
        "definition":{"definitionRevision":1,"protocolVersion":1,"catalogId":"hiboss.panel",
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

    func testAnEmptySnapshotDoesNotWipeThePublishedState() async throws {
        // The relay answers a fresh subscription with {"sequence":0,"task":{}} when no
        // producer has written yet. Treating that as state turned every server-backed
        // card into em-dashes. Uses a server-backed tile because receive() ignores any
        // tile without a definition revision, which is what made a first attempt vacuous.
        let model = PanelsModel(api: try StubPanelsService(populated: true), demoMode: false, autoload: false)
        await model.load()
        let tile = try XCTUnwrap(model.tiles.first)
        XCTAssertNotNil(tile.definitionRevision, "a server-backed tile carries a revision")
        let before = panelValue(at: "/task", in: tile.store.state)
        XCTAssertNotNil(before)

        model.receive(.snapshot(PanelRelaySnapshot(
            panelID: tile.id, definitionRevision: 1, epoch: "e1", sequence: 0, task: .object([:])
        )), for: tile.id)

        XCTAssertEqual(panelValue(at: "/task", in: tile.store.state), before,
                       "an empty snapshot at sequence zero must leave the published state alone")
    }
}
