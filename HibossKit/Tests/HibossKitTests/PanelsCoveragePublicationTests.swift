// Tests immediate model publication when relay evidence completes or revokes coverage.
// Exports PanelsCoveragePublicationTests with the clock disabled.
// Dependencies: Combine, XCTest, and real PanelsModel relay installation.

import Combine
import XCTest
@testable import HibossKit

@MainActor
final class PanelsCoveragePublicationTests: XCTestCase {
    func testFinalRelaySnapshotPublishesCoverageWithoutClock() throws {
        let model = PanelsModel(demoMode: false, autoload: false)
        model.clockTask?.cancel()
        let fixture = try XCTUnwrap(PanelFixtures.load().all.first)
        model.tiles = (0..<2).map {
            PanelTile(id: "tile-\($0)", fixture: fixture, store: PanelStore(fixture: fixture),
                      producer: nil, agentID: "agent", agentName: nil, sessionLabel: nil,
                      definitionRevision: 1, order: $0)
        }
        model.loadState = .loaded
        model.receive(snapshot(for: "tile-0"), for: "tile-0")
        XCTAssertFalse(model.tiles.allSatisfy { model.hasPanelCoverage(for: $0) })
        var publications = 0
        let observer = model.objectWillChange.sink { publications += 1 }
        defer { observer.cancel() }
        model.receive(snapshot(for: "tile-1"), for: "tile-1")
        XCTAssertTrue(model.tiles.allSatisfy { model.hasPanelCoverage(for: $0) })
        XCTAssertGreaterThan(publications, 0, "The final frame must redraw Today without a clock tick")
        publications = 0
        model.liveSubscriptions.remove("tile-1")
        XCTAssertFalse(model.hasPanelCoverage(for: model.tiles[1]))
        XCTAssertGreaterThan(publications, 0, "Socket loss must redraw coverage immediately")
    }

    func testCoverageInputsPublishWithoutUnrelatedModelChanges() {
        let model = PanelsModel(demoMode: false, autoload: false)
        model.clockTask?.cancel()
        var publications = 0
        let observer = model.objectWillChange.sink { publications += 1 }
        defer { observer.cancel() }
        model.isWallConnected = true
        XCTAssertGreaterThan(publications, 0)
        publications = 0
        model.isFetching = true
        XCTAssertGreaterThan(publications, 0)
    }

    private func snapshot(for id: String) -> PanelRelayFrame {
        .snapshot(PanelRelaySnapshot(panelID: id, definitionRevision: 1, epoch: "epoch", sequence: 0,
                                     task: .object([:]), observationVersion: 1))
    }
}
