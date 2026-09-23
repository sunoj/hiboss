// Exercises questionnaire freshness against the real PanelsModel and held API calls.
// Covers invalidation ordering, coalescing, connectivity, failures, and demo coverage.
// Dependencies: XCTest, HibossKit, and a controlled in-memory panel service.

import Combine
import XCTest
@testable import HibossKit

@MainActor
final class PanelsQuestionnaireCoverageTests: XCTestCase {
    func testOldEmptyFetchCannotReplaceRowsOrCompleteCoverageAfterWallInvalidation() async {
        let api = ControlledQuestionnaireAPI()
        let model = makeModel(api)
        await api.setQuestions([Self.request])
        await model.load()
        XCTAssertTrue(model.hasCompleteQuestionnaires)
        var completedSnapshots = 0
        let observation = model.$hasCompleteQuestionnaires.dropFirst().filter { $0 }
            .sink { _ in completedSnapshots += 1 }
        defer { observation.cancel() }
        await api.holdQuestions(returning: [])
        let old = Task { await model.load() }
        await api.waitForQuestions()
        await api.holdMetadata()
        model.receiveWall(.wallChanged)
        model.receiveWall(.wallChanged)
        XCTAssertFalse(model.hasCompleteQuestionnaires)
        await api.releaseQuestions()
        await old.value
        let followup = model.reconciliationTask
        await api.waitForMetadata()
        XCTAssertFalse(model.hasCompleteQuestionnaires)
        XCTAssertEqual(completedSnapshots, 0, "No transient all-clear may be published")
        XCTAssertEqual(model.pendingQuestionnaires, [Self.request])
        await api.releaseMetadata()
        await followup?.value
        XCTAssertTrue(model.hasCompleteQuestionnaires)
        XCTAssertEqual(model.pendingQuestionnaires, [Self.request])
        let count = await api.questionFetchCount
        XCTAssertEqual(count, 3, "Repeated invalidations coalesce into one follow-up")
        XCTAssertEqual(completedSnapshots, 1)
    }

    func testDisconnectRequiresAcknowledgedReconnectAndCurrentFetch() async {
        let api = ControlledQuestionnaireAPI()
        let model = makeModel(api)
        attachWall(to: model)
        await model.load()
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertFalse(model.hasCompleteQuestionnaires)
        model.wallConnectivityChanged(true)
        await model.reconciliationTask?.value
        XCTAssertTrue(model.hasCompleteQuestionnaires)
        model.wallConnectivityChanged(false)
        XCTAssertFalse(model.hasCompleteQuestionnaires)
        await model.reconciliationTask?.value
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertFalse(model.hasCompleteQuestionnaires, "HTTP success while disconnected is insufficient")
        await api.holdQuestions(returning: [])
        model.wallConnectivityChanged(true)
        let reconnect = model.reconciliationTask
        await api.waitForQuestions()
        XCTAssertFalse(model.hasCompleteQuestionnaires)
        await api.releaseQuestions()
        await reconnect?.value
        XCTAssertTrue(model.hasCompleteQuestionnaires)
    }

    func testDisconnectRejectsInFlightEmptyFetch() async {
        let api = ControlledQuestionnaireAPI()
        let model = makeModel(api)
        attachWall(to: model)
        model.wallConnectivityChanged(true)
        await model.reconciliationTask?.value
        await api.holdQuestions(returning: [])
        let old = Task { await model.refreshPendingQuestionnaires() }
        await api.waitForQuestions()
        model.wallConnectivityChanged(false)
        await api.releaseQuestions()
        await old.value
        XCTAssertFalse(model.hasCompleteQuestionnaires)
        await model.reconciliationTask?.value
        XCTAssertFalse(model.hasCompleteQuestionnaires)
    }

    func testConnectionChangeRejectsOldFetchAndPreservesKnownRows() async {
        let api = ControlledQuestionnaireAPI()
        let model = makeModel(api)
        await api.setQuestions([Self.request])
        await model.load()
        await api.holdQuestions(returning: [])
        let old = Task { await model.refreshPendingQuestionnaires() }
        await api.waitForQuestions()
        model.connectionDidChange()
        XCTAssertFalse(model.hasCompleteQuestionnaires)
        await api.releaseQuestions()
        await old.value
        XCTAssertEqual(model.pendingQuestionnaires, [Self.request])
        XCTAssertFalse(model.hasCompleteQuestionnaires)
        await model.reconciliationTask?.value
        XCTAssertTrue(model.hasCompleteQuestionnaires)
    }

    func testOverlappingRefreshSupersedesOldFetchAndReconciles() async {
        let api = ControlledQuestionnaireAPI()
        let model = makeModel(api)
        await api.setQuestions([Self.request])
        await model.load()
        await api.holdQuestions(returning: [])
        let old = Task { await model.refreshPendingQuestionnaires() }
        await api.waitForQuestions()
        await model.refreshPendingQuestionnaires()
        await api.releaseQuestions()
        await old.value
        XCTAssertFalse(model.hasCompleteQuestionnaires)
        XCTAssertEqual(model.pendingQuestionnaires, [Self.request])
        await model.reconciliationTask?.value
        XCTAssertTrue(model.hasCompleteQuestionnaires)
        XCTAssertEqual(model.pendingQuestionnaires, [Self.request])
    }

    func testMetadataReloadImmediatelyRevokesCoverageAndFailureKeepsRows() async {
        let api = ControlledQuestionnaireAPI()
        let model = makeModel(api)
        await api.setQuestions([Self.request])
        await model.load()
        await api.holdMetadata()
        await api.failQuestions()
        let reload = Task { await model.load() }
        await api.waitForMetadata()
        XCTAssertFalse(model.hasCompleteQuestionnaires)
        XCTAssertEqual(model.pendingQuestionnaires, [Self.request])
        await api.releaseMetadata()
        await reload.value
        XCTAssertNotNil(model.questionnaireError)
        XCTAssertFalse(model.hasCompleteQuestionnaires)
        XCTAssertEqual(model.pendingQuestionnaires, [Self.request])
    }

    func testInjectedServiceWithoutWallCompletesAfterSuccessfulEmptyFetch() async {
        let model = makeModel(ControlledQuestionnaireAPI())
        XCTAssertFalse(model.hasCompleteQuestionnaires)
        await model.load()
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertNil(model.wallConnection)
        XCTAssertTrue(model.hasCompleteQuestionnaires)
    }

    func testInvalidationDuringMetadataFetchDefersQuestionnairesToFollowup() async {
        let api = ControlledQuestionnaireAPI()
        let model = makeModel(api)
        await model.load()
        await api.holdMetadata()
        let old = Task { await model.load() }
        await api.waitForMetadata()
        model.receiveWall(.wallChanged)
        await api.releaseMetadata()
        await old.value
        XCTAssertFalse(model.hasCompleteQuestionnaires)
        let count = await api.questionFetchCount
        XCTAssertEqual(count, 1, "Superseded metadata must not authorize a questionnaire fetch")
        await model.reconciliationTask?.value
        XCTAssertTrue(model.hasCompleteQuestionnaires)
    }

    func testPanelMetadataAndSubscriptionLossImmediatelyRevokeCoverage() async {
        let model = makeModel(ControlledQuestionnaireAPI())
        await model.load()
        model.receive(.metadataChanged, for: "panel")
        XCTAssertFalse(model.hasCompleteQuestionnaires)
        await model.reconciliationTask?.value
        XCTAssertTrue(model.hasCompleteQuestionnaires)
        model.receive(.subscriptionRevoked, for: "panel")
        XCTAssertFalse(model.hasCompleteQuestionnaires)
        await model.reconciliationTask?.value
        XCTAssertTrue(model.hasCompleteQuestionnaires)
    }

    func testStandaloneQuestionnaireFetchCannotBypassQueuedWallReconciliation() async {
        let api = ControlledQuestionnaireAPI()
        let model = makeModel(api)
        attachWall(to: model)
        model.wallConnectivityChanged(true)
        await model.reconciliationTask?.value
        XCTAssertTrue(model.hasCompleteQuestionnaires)
        model.receiveWall(.wallChanged)
        await model.refreshPendingQuestionnaires()
        XCTAssertFalse(model.hasCompleteQuestionnaires)
        await model.reconciliationTask?.value
        XCTAssertTrue(model.hasCompleteQuestionnaires)
    }

    private func makeModel(_ api: ControlledQuestionnaireAPI) -> PanelsModel {
        let model = PanelsModel(api: api, demoMode: false, autoload: false)
        model.clockTask?.cancel()
        return model
    }

    private func attachWall(to model: PanelsModel) {
        let config = ConnectionConfig(serverURL: URL(string: "https://example.invalid")!, bossToken: "test")
        model.wallConnection = PanelRelayConnection(config: config, panelID: "wall", isWall: true,
                                                   onFrame: { _ in }, onDisconnect: {})
    }

    private static let request = PendingQuestionnaire(
        requestId: "request", panelId: "panel", requestRevision: 1, title: "Choose dataset",
        blocking: true, expiresAt: nil, createdAt: "2026-09-23T00:00:00Z"
    )
}

private actor ControlledQuestionnaireAPI: PanelsServing, QuestionnaireServing {
    nonisolated let questionnaireScope = "coverage-tests"
    private var questions: [PendingQuestionnaire] = []
    private var heldQuestions: [PendingQuestionnaire]?
    private var questionsGate: CheckedContinuation<Void, Never>?
    private var questionsStarted: CheckedContinuation<Void, Never>?
    private var holdsMetadata = false
    private var metadataGate: CheckedContinuation<Void, Never>?
    private var metadataStarted: CheckedContinuation<Void, Never>?
    private var fails = false
    private(set) var questionFetchCount = 0

    func setQuestions(_ value: [PendingQuestionnaire]) { questions = value }
    func holdQuestions(returning value: [PendingQuestionnaire]) { heldQuestions = value }
    func holdMetadata() { holdsMetadata = true }
    func failQuestions() { fails = true }
    func releaseQuestions() { questionsGate?.resume(); questionsGate = nil }
    func releaseMetadata() { metadataGate?.resume(); metadataGate = nil }

    func waitForQuestions() async {
        if questionsGate != nil { return }
        await withCheckedContinuation { questionsStarted = $0 }
    }

    func waitForMetadata() async {
        if metadataGate != nil { return }
        await withCheckedContinuation { metadataStarted = $0 }
    }

    func fetchPendingQuestionnaires() async throws -> [PendingQuestionnaire] {
        questionFetchCount += 1
        if let held = heldQuestions {
            heldQuestions = nil
            await withCheckedContinuation {
                questionsGate = $0
                questionsStarted?.resume()
                questionsStarted = nil
            }
            return held
        }
        if fails { throw HibossAPIError.invalidResponse }
        return questions
    }

    func fetchPanels() async throws -> [PanelMetadata] {
        if holdsMetadata {
            holdsMetadata = false
            await withCheckedContinuation {
                metadataGate = $0
                metadataStarted?.resume()
                metadataStarted = nil
            }
        }
        return []
    }

    func fetchPanel(_ panelID: String) async throws -> PanelDetail { throw HibossAPIError.invalidResponse }
    func fetchPanelState(_ panelID: String) async throws -> PanelRelaySnapshot { throw HibossAPIError.invalidResponse }
    func updatePanelPreference(_ panelID: String, command: PanelPreferenceCommand) async throws -> PanelPreference {
        throw HibossAPIError.invalidResponse
    }
    func fetchQuestionnaires(panelID: String) async throws -> [QuestionnaireRecord] { [] }
    func fetchQuestionnaire(_ id: String) async throws -> QuestionnaireRecord { throw HibossAPIError.invalidResponse }
    func fetchQuestionnaireSubmission(requestID: String, submissionID: String) async throws -> QuestionnaireSubmission {
        throw HibossAPIError.invalidResponse
    }
    func submitQuestionnaire(_ request: QuestionnaireRecord, bossID: String,
                             submissionID: String, answers: PanelValue) async throws -> QuestionnaireReceipt {
        throw HibossAPIError.invalidResponse
    }
}
