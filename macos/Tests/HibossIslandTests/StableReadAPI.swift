// Holds background reads without timing guesses while preserving healthy streams.
// Exports StableReadAPI for cached-content regressions across the main window.
// Dependencies: HibossKit service contracts and existing local panel fixtures.

import Foundation
import HibossKit

actor StableReadAPI: BossServing, PanelsServing, QuestionnaireServing, JoinRequestServing {
    enum Read: Hashable { case history, panels, joins, questions, editor }
    nonisolated let questionnaireScope = "stable-surfaces"
    func fetchBossIdentity() async throws -> BossIdentity { BossIdentity(id: "boss_1", role: "admin") }
    let history: [HistoryMessage]
    let joins: [JoinRequest]
    private let panelAPI: StubPanelsService
    private var held: Set<Read> = []
    private var gates: [Read: CheckedContinuation<Void, Never>] = [:]
    private var waiters: [Read: CheckedContinuation<Void, Never>] = [:]
    private var stream: AsyncThrowingStream<BossEvent, Error>.Continuation?
    private var failing: Set<Read> = []
    private var records: [QuestionnaireRecord] = []
    private(set) var editorReads = 0

    init(history: [HistoryMessage] = [], joins: [JoinRequest] = [], populatedPanels: Bool = false) throws {
        self.history = history
        self.joins = joins
        panelAPI = populatedPanels ? try StubPanelsService(populated: true) : StubPanelsService()
    }

    func hold(_ read: Read) { held.insert(read) }
    func fail(_ read: Read) { failing.insert(read) }
    func succeed(_ read: Read) { failing.remove(read) }
    func setRecords(_ value: [QuestionnaireRecord]) { records = value }
    func waitUntilHeld(_ read: Read) async {
        if gates[read] != nil { return }
        await withCheckedContinuation { waiters[read] = $0 }
    }
    func release(_ read: Read) {
        held.remove(read)
        gates.removeValue(forKey: read)?.resume()
    }
    private func read(_ read: Read) async throws {
        if held.contains(read) {
            await withCheckedContinuation { continuation in
                gates[read] = continuation
                waiters.removeValue(forKey: read)?.resume()
            }
        }
        if failing.contains(read) { throw HibossAPIError.invalidResponse }
    }

    func fetchHistory() async throws -> [HistoryMessage] {
        try await read(.history)
        return history
    }
    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> {
        let pair = AsyncThrowingStream<BossEvent, Error>.makeStream()
        stream = pair.continuation
        return pair.stream
    }
    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func fetchMessage(_ id: MessageID) async throws -> MessageDetail {
        guard let message = history.first(where: { $0.id == id }) else {
            throw HibossAPIError.invalidResponse
        }
        return MessageDetail(message: message, replies: [])
    }
    func reply(to id: MessageID, with choice: String) async throws -> ReplyOutcome { .accepted }

    func fetchPanels() async throws -> [PanelMetadata] {
        try await read(.panels)
        return try await panelAPI.fetchPanels()
    }
    func fetchPanel(_ id: String) async throws -> PanelDetail { try await panelAPI.fetchPanel(id) }
    func fetchPanelState(_ id: String) async throws -> PanelRelaySnapshot {
        try await panelAPI.fetchPanelState(id)
    }
    func updatePanelPreference(_ id: String, command: PanelPreferenceCommand) async throws
        -> PanelPreference {
        throw HibossAPIError.invalidResponse
    }
    func fetchPendingQuestionnaires() async throws -> [PendingQuestionnaire] {
        try await read(.questions)
        return []
    }
    func fetchQuestionnaires(panelID: String) async throws -> [QuestionnaireRecord] {
        editorReads += 1
        try await read(.editor)
        return records
    }
    func fetchQuestionnaire(_ id: String) async throws -> QuestionnaireRecord {
        throw HibossAPIError.invalidResponse
    }
    func fetchQuestionnaireSubmission(requestID: String, submissionID: String) async throws
        -> QuestionnaireSubmission { throw HibossAPIError.invalidResponse }
    func submitQuestionnaire(_ request: QuestionnaireRecord, bossID: String, submissionID: String,
                             answers: PanelValue) async throws -> QuestionnaireReceipt {
        throw HibossAPIError.invalidResponse
    }

    func listPendingJoinRequests() async throws -> [JoinRequest] {
        try await read(.joins)
        return joins
    }
    func approveJoinRequest(id: String) async throws -> JoinApproval { throw JoinRequestError.notFound }
    func rejectJoinRequest(id: String) async throws { throw JoinRequestError.notFound }
}
