// Panel retry regressions for held discovery and questionnaire reads.
// Exports PanelRetryTests; retries must start a new read and ignore superseded completions.
// Dependencies: XCTest, HibossKit PanelsModel and continuation-controlled services.

import HibossKit
import XCTest

@MainActor
final class PanelRetryTests: XCTestCase {
    func testRetrySupersedesHeldPanelDiscovery() async {
        let second = expectation(description: "second discovery")
        let first = expectation(description: "first discovery")
        let api = HeldPanelReads(holdPanels: true, first: first, second: second)
        let model = PanelsModel(api: api, demoMode: false, autoload: false)
        let loading = Task { await model.load() }
        await fulfillment(of: [first], timeout: 2)
        let retry = Task { await model.retryLoading() }
        await fulfillment(of: [second], timeout: 2)
        let reads = await api.numberOfReads()
        XCTAssertEqual(reads, 2)
        await api.release(2)
        await retry.value
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertTrue(model.hasCompleteQuestionnaires)
        await api.release(1)
        await loading.value
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertTrue(model.hasCompleteQuestionnaires)
    }

    func testOldQuestionnaireReadCannotEndNewPendingState() async {
        let first = expectation(description: "first questionnaire read")
        let second = expectation(description: "second questionnaire read")
        let api = HeldPanelReads(holdPanels: false, first: first, second: second)
        let model = PanelsModel(api: api, demoMode: false, autoload: false)
        let loading = Task { await model.load() }
        await fulfillment(of: [first], timeout: 2)
        let retry = Task { await model.retryLoading() }
        await fulfillment(of: [second], timeout: 2)
        await api.release(1)
        await loading.value
        XCTAssertTrue(model.isLoadingQuestions)
        XCTAssertFalse(model.hasCompleteQuestionnaires)
        await api.release(2)
        await retry.value
        XCTAssertFalse(model.isLoadingQuestions)
        XCTAssertTrue(model.hasCompleteQuestionnaires)
    }
}

private actor HeldPanelReads: PanelsServing, QuestionnaireServing {
    nonisolated let questionnaireScope = "held-panel-reads"
    let holdPanels: Bool
    let first: XCTestExpectation
    let second: XCTestExpectation
    private var count = 0
    private var reads: [Int: CheckedContinuation<Void, Never>] = [:]

    init(holdPanels: Bool, first: XCTestExpectation, second: XCTestExpectation) {
        self.holdPanels = holdPanels
        self.first = first
        self.second = second
    }

    func numberOfReads() -> Int { count }
    func release(_ number: Int) { reads.removeValue(forKey: number)?.resume() }

    private func hold() async {
        count += 1
        let number = count
        await withCheckedContinuation { continuation in
            reads[number] = continuation
            (number == 1 ? first : second).fulfill()
        }
    }

    func fetchPanels() async throws -> [PanelMetadata] {
        if holdPanels { await hold() }
        return []
    }
    func fetchPendingQuestionnaires() async throws -> [PendingQuestionnaire] {
        if !holdPanels { await hold() }
        return []
    }
    func fetchPanel(_ panelID: String) async throws -> PanelDetail { throw HibossAPIError.invalidResponse }
    func fetchPanelState(_ panelID: String) async throws -> PanelRelaySnapshot {
        throw HibossAPIError.invalidResponse
    }
    func updatePanelPreference(_ panelID: String, command: PanelPreferenceCommand)
        async throws -> PanelPreference { throw HibossAPIError.invalidResponse }
    func fetchQuestionnaires(panelID: String) async throws -> [QuestionnaireRecord] { [] }
    func fetchQuestionnaire(_ id: String) async throws -> QuestionnaireRecord {
        throw HibossAPIError.invalidResponse
    }
    func fetchQuestionnaireSubmission(requestID: String, submissionID: String)
        async throws -> QuestionnaireSubmission { throw HibossAPIError.invalidResponse }
    func submitQuestionnaire(_ request: QuestionnaireRecord, bossID: String,
                             submissionID: String, answers: PanelValue)
        async throws -> QuestionnaireReceipt { throw HibossAPIError.invalidResponse }
}
