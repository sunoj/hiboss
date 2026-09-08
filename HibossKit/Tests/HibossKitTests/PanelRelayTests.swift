// Verifies native v2 checkpoint ordering, epoch handoff, and observation rules.
// Exports PanelRelayTests with duplicate/gap and ownership regression coverage.
// Dependencies: XCTest and HibossKit relay contracts.

import XCTest
@testable import HibossKit

final class PanelRelayTests: XCTestCase {
    func testDuplicatePatchIsIgnoredAndGapRequestsResync() {
        var state = baseline()
        XCTAssertEqual(state.apply(.patch(.init(checkpoint: checkpoint(sequence: 1), baseSequence: 0))), .ignored)
        XCTAssertEqual(state.apply(.patch(.init(checkpoint: checkpoint(sequence: 3), baseSequence: 2))), .resyncRequired)
        XCTAssertEqual(state.sequence, 1)
    }
    func testSnapshotInstallsNewEpochAtSequenceZeroAndRejectsRetiredEpoch() {
        var state = baseline()
        XCTAssertEqual(state.apply(.snapshot(checkpoint(epoch: "new", sequence: 0))), .installed)
        XCTAssertEqual(state.sequence, 0)
        XCTAssertEqual(state.apply(.snapshot(checkpoint(sequence: 9))), .rejected)
        XCTAssertEqual(state.epoch, "new")
    }
    func testPatchFromDifferentEpochCannotInstall() {
        var state = baseline()
        XCTAssertEqual(state.apply(.patch(.init(checkpoint: checkpoint(epoch: "foreign", sequence: 2), baseSequence: 1))), .rejected)
    }
    func testUnchangedObservationKeepsSequenceAndUpdatesFreshness() {
        var state = baseline()
        let observation = checkpoint(sequence: 1, observation: 2)
        XCTAssertEqual(state.apply(.observation(observation)), .applied)
        XCTAssertEqual(state.sequence, 1)
        XCTAssertEqual(state.checkpoint?.observationVersion, 2)
        XCTAssertEqual(state.apply(.observation(checkpoint(sequence: 1, observation: 1))), .rejected)
    }
    func testCheckpointCannotCrossPanelOrDefinitionBoundary() {
        var state = baseline()
        let wrong = PanelRelaySnapshot(panelID: "other", definitionRevision: 1, epoch: nil, sequence: 0, task: .null)
        XCTAssertEqual(state.apply(.snapshot(wrong)), .rejected)
    }
    @MainActor
    func testTaskSnapshotDoesNotReplaceLocalFormDraft() throws {
        let fixture = try XCTUnwrap(PanelFixtures.load().all.first)
        let store = PanelStore(fixture: fixture)
        let form = panelValue(at: "/form", in: store.state)
        store.replaceTask(.object(["items": .array([.string("a"), .string("b")])]))
        XCTAssertEqual(panelValue(at: "/form", in: store.state), form)
        XCTAssertEqual(panelValue(at: "/task/items", in: store.state), .array([.string("a"), .string("b")]))
    }
    private func baseline() -> PanelRelayState {
        var state = PanelRelayState(panelID: "panel-1", definitionRevision: 4)
        _ = state.apply(.snapshot(checkpoint(sequence: 1)))
        return state
    }
    private func checkpoint(epoch: String = "epoch-1", sequence: Int, observation: Int = 1) -> PanelRelaySnapshot {
        PanelRelaySnapshot(panelID: "panel-1", definitionRevision: 4, epoch: epoch, sequence: sequence,
            task: .object(["count": .number(1)]), observationVersion: observation)
    }
}
