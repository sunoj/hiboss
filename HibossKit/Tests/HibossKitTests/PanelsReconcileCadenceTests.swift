// Verifies the fallback reconciliation cadence that recovers lost wall signals.
// Exports PanelsReconcileCadenceTests; dependencies: XCTest and PanelsModel.

import XCTest
@testable import HibossKit

@MainActor
final class PanelsReconcileCadenceTests: XCTestCase {
    func testConnectedWallReconcilesRarelyAndDisconnectedWallKeepsDiscoveryRate() {
        let model = PanelsModel(demoMode: false, autoload: false)
        model.clockTask?.cancel()
        let reconciled = Date()
        model.lastReconciled = reconciled
        model.isWallConnected = false
        XCTAssertFalse(model.needsFallbackReconcile(at: reconciled.addingTimeInterval(9)))
        XCTAssertTrue(model.needsFallbackReconcile(at: reconciled.addingTimeInterval(11)))
        model.isWallConnected = true
        XCTAssertFalse(model.needsFallbackReconcile(at: reconciled.addingTimeInterval(11)),
            "A connected wall is signalled; the ten-second poll would only repeat the list")
        XCTAssertFalse(model.needsFallbackReconcile(at: reconciled.addingTimeInterval(59)))
        XCTAssertTrue(model.needsFallbackReconcile(at: reconciled.addingTimeInterval(61)))
    }

    func testFallbackNeverOverlapsAFetchOrRunsInDemoMode() {
        let model = PanelsModel(demoMode: false, autoload: false)
        model.clockTask?.cancel()
        model.lastReconciled = .distantPast
        model.isFetching = true
        XCTAssertFalse(model.needsFallbackReconcile(at: Date()))
        let demo = PanelsModel(demoMode: true, autoload: false)
        demo.clockTask?.cancel()
        demo.lastReconciled = .distantPast
        XCTAssertFalse(demo.needsFallbackReconcile(at: Date()))
    }
}
