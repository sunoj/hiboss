// Verifies foreground coalescing, eager panels, and required-input readiness barriers.
// Exports TodayStartupTests with deterministic service counts and held network work.
// Dependencies: XCTest, InboxStore, ConnectedPanelsStore, and controlled services.

import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class TodayStartupTests: XCTestCase {
    func testForegroundDoesNotQueueHistoryOrSupersedeRequiredInputsDuringLaunch() async {
        let api = ControlledInputAPI()
        await api.holdHistory()
        await api.holdNextFetch(returning: [])
        let store = InboxStore(decisionAlertsEnabled: false)
        store.start(api: api)
        defer { store.stop() }
        await api.waitForHistory()
        await api.waitForHeldFetch()
        let version = store.requiredFetchVersion
        store.refreshHistory()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(store.requiredFetchVersion, version)
        await api.releaseFetch()
        await api.releaseHistory()
        await store.historyTask?.value
        let reads = await api.historyReads
        let requests = await api.requiredFetchCount()
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(requests, 1)
        XCTAssertTrue(store.didLoad)
    }

    func testPanelStartupDoesNotWaitForHomeAppearance() async {
        let api = StartupPanelsAPI()
        let store = ConnectedPanelsStore()
        store.start(api: api)
        await store.startup?.value
        let reads = await api.panelReads
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(store.model.loadState, .loaded)
        store.stop()
    }

    func testReadyRechecksSnapshotFetchedBeforeInitialStreamScan() async {
        let api = ControlledInputAPI()
        let store = InboxStore(decisionAlertsEnabled: false)
        store.api = api
        store.startRequiredInputs(api)
        defer { store.stop() }
        await api.waitForStream(0)
        let retired = HistoryMessage(id: "old", body: "Choose", direction: "agent_to_boss",
                                     status: "sent", priority: "low", mode: "blocking",
                                     createdAt: Date().ISO8601Format())
        await api.setResponse([retired])
        await store.refreshRequiredInputs()
        XCTAssertFalse(store.hasCompleteRequiredInputs)
        // An initial empty stream scan has no resolved event for an earlier HTTP-only row.
        await api.setResponse([])
        await api.sendReady(to: 0)
        for _ in 0..<200 {
            if store.hasCompleteRequiredInputs && store.requiredInputs.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(store.requiredInputs.isEmpty)
        XCTAssertTrue(store.hasCompleteRequiredInputs)
        let reads = await api.requiredFetchCount()
        XCTAssertEqual(reads, 2, "Pre-ready HTTP has no stream watermark proving its currency")
    }

    func testReadyCrossingHeldSnapshotWithholdsCoverageUntilPostReadyRead() async {
        let api = ControlledInputAPI()
        let store = InboxStore(decisionAlertsEnabled: false)
        store.api = api
        store.startRequiredInputs(api)
        defer { store.stop() }
        await api.waitForStream(0)
        let retired = HistoryMessage(id: "retired", body: "Choose", direction: "agent_to_boss",
            status: "sent", priority: "low", mode: "blocking", createdAt: Date().ISO8601Format())
        await api.holdNextFetch(returning: [retired])
        let beforeReady = Task { await store.refreshRequiredInputs() }
        await api.waitForHeldFetch()
        await api.sendReady(to: 0)
        for _ in 0..<100 { await Task.yield() }
        XCTAssertTrue(store.requiredInputReady)
        await api.releaseFetchAndHoldNext(returning: [])
        await beforeReady.value
        for _ in 0..<100 { await Task.yield() }
        XCTAssertFalse(store.hasCompleteRequiredInputs, "Pre-ready HTTP cannot certify an empty stream scan")
        let reads = await api.requiredFetchCount()
        XCTAssertEqual(reads, 2, "Exactly one post-ready read must be coalesced")
        await api.sendReady(to: 0)
        for _ in 0..<100 { await Task.yield() }
        let duplicateReads = await api.requiredFetchCount()
        XCTAssertEqual(duplicateReads, 2, "Duplicate ready must retain the post-ready read")
        await api.releaseFetch()
        await store.requiredFetchTask?.value
        XCTAssertTrue(store.requiredInputs.isEmpty)
        XCTAssertTrue(store.hasCompleteRequiredInputs)
    }

    func testReadyBurstCoalescesOneReconciliation() async {
        let api = ControlledInputAPI()
        await api.holdNextFetch(returning: [])
        let store = InboxStore(decisionAlertsEnabled: false)
        store.api = api
        store.startRequiredInputs(api)
        defer { store.stop() }
        await api.sendReadyBurst(to: 0)
        await api.waitForHeldFetch()
        for _ in 0..<100 { await Task.yield() }
        let reads = await api.requiredFetchCount()
        XCTAssertEqual(reads, 1)
        await api.releaseFetch()
        await store.requiredFetchTask?.value
        XCTAssertTrue(store.hasCompleteRequiredInputs)
    }
}

private actor StartupPanelsAPI: PanelsServing, QuestionnaireServing {
    nonisolated let questionnaireScope = "eager-startup"
    private(set) var panelReads = 0
    func fetchPanels() async throws -> [PanelMetadata] {
        panelReads += 1
        return []
    }
    func fetchPendingQuestionnaires() async throws -> [PendingQuestionnaire] { [] }
    func fetchPanel(_ panelID: String) async throws -> PanelDetail { throw HibossAPIError.invalidResponse }
    func fetchPanelState(_ panelID: String) async throws -> PanelRelaySnapshot {
        throw HibossAPIError.invalidResponse
    }
    func updatePanelPreference(_ panelID: String, command: PanelPreferenceCommand) async throws
        -> PanelPreference { throw HibossAPIError.invalidResponse }
    func fetchQuestionnaires(panelID: String) async throws -> [QuestionnaireRecord] { [] }
    func fetchQuestionnaire(_ id: String) async throws -> QuestionnaireRecord {
        throw HibossAPIError.invalidResponse
    }
    func fetchQuestionnaireSubmission(requestID: String, submissionID: String) async throws
        -> QuestionnaireSubmission { throw HibossAPIError.invalidResponse }
    func submitQuestionnaire(_ request: QuestionnaireRecord, bossID: String,
                             submissionID: String, answers: PanelValue) async throws -> QuestionnaireReceipt {
        throw HibossAPIError.invalidResponse
    }
}
