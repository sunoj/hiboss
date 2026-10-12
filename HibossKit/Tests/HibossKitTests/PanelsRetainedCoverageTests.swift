// Verifies a known discovery failure revokes retained display coverage immediately.
// Holds metadata through the production PanelsModel while questionnaires fail.
// Dependencies: XCTest and ControlledQuestionnaireAPI.

import XCTest
@testable import HibossKit

@MainActor
final class PanelsRetainedCoverageTests: XCTestCase {
    func testKnownQuestionnaireFailureRevokesDisplayWhileMetadataIsHeld() async {
        let api = ControlledQuestionnaireAPI()
        let model = PanelsModel(api: api, demoMode: false, autoload: false)
        model.clockTask?.cancel()
        await model.load()
        XCTAssertTrue(model.hasDisplayCoverage)
        await api.holdMetadata()
        await api.failQuestions()
        let reload = Task { await model.load() }
        await api.waitForMetadata()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertNotNil(model.questionnaireError)
        XCTAssertTrue(model.isFetching)
        XCTAssertFalse(model.hasDisplayCoverage, "Known question failure must suppress all-clear")
        await api.releaseMetadata()
        await reload.value
        XCTAssertNotNil(model.questionnaireError)
        XCTAssertFalse(model.hasDisplayCoverage)
    }
}
