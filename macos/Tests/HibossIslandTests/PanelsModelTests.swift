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
}

private actor StubPanelsService: PanelsServing {
    enum Failure: Error, LocalizedError {
        case unavailable

        var errorDescription: String? { "The panel service is unavailable." }
    }

    let failure: Failure?

    init(failure: Failure? = nil) { self.failure = failure }

    func fetchPanels() async throws -> [PanelMetadata] {
        if let failure { throw failure }
        return []
    }

    func fetchPanel(_ panelID: String) async throws -> PanelDetail {
        throw Failure.unavailable
    }
}
