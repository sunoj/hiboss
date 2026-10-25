// Controls metadata order while keeping the native message stream healthy.
// Exports TodayStartupAPI for hosted MainView account and coverage regressions.
// Dependencies: existing StubPanelsService fixtures and HibossKit service protocols.

import Foundation
import HibossKit
import XCTest

actor TodayStartupAPI: PanelsServing, QuestionnaireServing, BossServing {
    nonisolated let questionnaireScope = "mac-startup"
    func fetchBossIdentity() async throws -> BossIdentity { BossIdentity(id: "boss", role: "admin") }
    private let panels: StubPanelsService
    private var gate: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    private var hold = true
    private var fails = false
    private var populated = false
    private var stream: AsyncThrowingStream<BossEvent, Error>.Continuation?
    private(set) var panelReads = 0

    init() throws { panels = try StubPanelsService(populated: true) }
    func setPopulated(_ value: Bool) { populated = value }
    func failPanels() { fails = true }
    func waitForPanels() async {
        if gate != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func releasePanels() {
        gate?.resume()
        gate = nil
    }
    func fetchPanels() async throws -> [PanelMetadata] {
        panelReads += 1
        let snapshot = populated ? try await panels.fetchPanels() : []
        if hold {
            hold = false
            await withCheckedContinuation {
                gate = $0
                waiter?.resume()
                waiter = nil
            }
        }
        if fails { throw HibossAPIError.invalidResponse }
        return snapshot
    }
    func fetchPanel(_ panelID: String) async throws -> PanelDetail { try await panels.fetchPanel(panelID) }
    func fetchPanelState(_ panelID: String) async throws -> PanelRelaySnapshot {
        try await panels.fetchPanelState(panelID)
    }
    func updatePanelPreference(_ panelID: String, command: PanelPreferenceCommand) async throws
        -> PanelPreference { throw HibossAPIError.invalidResponse }
    func fetchPendingQuestionnaires() async throws -> [PendingQuestionnaire] { [] }
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
    func fetchHistory() async throws -> [HistoryMessage] { [] }
    func fetchMessage(_ id: MessageID) async throws -> MessageDetail { throw HibossAPIError.invalidResponse }
    func reply(to id: MessageID, with choice: String) async throws -> ReplyOutcome { .accepted }
    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> {
        let pair = AsyncThrowingStream<BossEvent, Error>.makeStream()
        stream = pair.continuation
        return pair.stream
    }
}
