// Tests ordered live-panel application and its namespace boundary.
// Exports: PanelRelayTests covering snapshots, patches, gaps, and epochs.
// Dependencies: XCTest and HibossKit relay contracts.

import XCTest
@testable import HibossKit

final class PanelRelayTests: XCTestCase {
    func testOutOfOrderSequenceIsIgnored() {
        var state = baseline()

        let result = state.apply(patch(sequence: 1, baseSequence: 0, value: 8))

        XCTAssertEqual(result, .ignored)
        XCTAssertEqual(state.sequence, 1)
        XCTAssertEqual(state.task, .object(["count": .number(1)]))
    }

    func testGapRequestsResyncWithoutGuessing() {
        var state = baseline()

        let result = state.apply(patch(sequence: 3, baseSequence: 2, value: 8))

        XCTAssertEqual(result, .resyncRequired)
        XCTAssertEqual(state.sequence, 1)
        XCTAssertEqual(state.task, .object(["count": .number(1)]))
    }

    func testMismatchedEpochIsRejected() {
        var state = baseline()

        let result = state.apply(PanelRelayFrame.patch(PanelRelayPatch(
            panelID: "panel-1", definitionRevision: 4, epoch: "epoch-2", baseSequence: 1,
            sequence: 2, operations: [PanelRelayOperation(operation: "replace", path: "/task/count", value: .number(2))]
        )))

        XCTAssertEqual(result, .rejected)
        XCTAssertEqual(state.sequence, 1)
    }

    func testTaskPatchCannotTouchFormNamespace() {
        var state = baseline()

        let result = state.apply(PanelRelayFrame.patch(PanelRelayPatch(
            panelID: "panel-1", definitionRevision: 4, epoch: "epoch-1", baseSequence: 1,
            sequence: 2, operations: [PanelRelayOperation(operation: "replace", path: "/form/name", value: .string("remote"))]
        )))

        XCTAssertEqual(result, .rejected)
        XCTAssertEqual(state.task, .object(["count": .number(1)]))
    }

    private func baseline() -> PanelRelayState {
        var state = PanelRelayState(panelID: "panel-1", definitionRevision: 4)
        _ = state.apply(.snapshot(PanelRelaySnapshot(
            panelID: "panel-1", definitionRevision: 4, epoch: "epoch-1", sequence: 1,
            task: .object(["count": .number(1)])
        )))
        return state
    }

    private func patch(sequence: Int, baseSequence: Int, value: Double) -> PanelRelayFrame {
        .patch(PanelRelayPatch(
            panelID: "panel-1", definitionRevision: 4, epoch: "epoch-1", baseSequence: baseSequence,
            sequence: sequence, operations: [PanelRelayOperation(operation: "replace", path: "/task/count", value: .number(value))]
        ))
    }
}
