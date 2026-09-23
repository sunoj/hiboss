// Covers mixed Home attention counts, questionnaire routing, and text reply lifecycle.
// Exports HomeAttentionFlowTests; uses the real InboxStore and PanelsModel.
// Dependencies: XCTest, HiBoss, HibossKit, and an in-memory boss service.

import XCTest
@testable import HiBoss
@testable import HibossKit

@MainActor
final class HomeAttentionFlowTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testHomeRequiresCurrentQuestionnaireCoverageEvenWithHealthyMessageCoverage() async {
        let inbox = InboxStore(decisionAlertsEnabled: false)
        inbox.start(api: TextReplyAPI(messages: []))
        defer { inbox.stop() }
        await inbox.refresh()
        let panels = PanelsModel(api: DemoHomePanelsAPI(), demoMode: false, autoload: false)
        panels.clockTask?.cancel()
        let home = HomeView(inbox: inbox, sessionAPI: nil, panels: panels)
        await panels.load()
        XCTAssertTrue(inbox.hasCompleteRequiredInputs)
        XCTAssertNil(home.attentionStatus)
        panels.receiveWall(.wallChanged)
        XCTAssertEqual(home.attentionStatus, "Checking for requests…")
        await panels.reconciliationTask?.value
        XCTAssertNil(home.attentionStatus)
        let config = ConnectionConfig(serverURL: URL(string: "https://example.invalid")!, bossToken: "test")
        panels.wallConnection = PanelRelayConnection(config: config, panelID: "wall", isWall: true,
                                                     onFrame: { _ in }, onDisconnect: {})
        panels.wallConnectivityChanged(false)
        await panels.reconciliationTask?.value
        XCTAssertEqual(panels.loadState, .loaded)
        XCTAssertEqual(home.attentionStatus, "Checking for requests…")
        panels.wallConnectivityChanged(true)
        XCTAssertNotNil(home.attentionStatus)
        await panels.reconciliationTask?.value
        XCTAssertNil(home.attentionStatus)
        panels.connectionDidChange()
        XCTAssertNotNil(home.attentionStatus)
        await panels.reconciliationTask?.value
    }

    func testQuestionnairesCountOnceAcrossPanelsAndDoNotDependOnWallVisibility() {
        let requests = [request("shared", panel: "b"), request("shared", panel: "a"),
                        request("optional", blocking: false), request("expired", expires: now),
                        request("terminal", panel: "done")]
        let snapshot = HomeAttentionSnapshot(messages: [ask], questionnaires: requests,
                                             terminalPanelIDs: ["done"], now: now)
        XCTAssertEqual(snapshot.count, 2)
        XCTAssertEqual(Set(snapshot.questionnaires.map(\.requestId)), ["shared"])
        XCTAssertEqual(HomeAttentionSnapshot(messages: [], questionnaires: [request("optional", blocking: false)],
                                             now: now).count, 0)
        XCTAssertEqual(snapshot.questionnaires.first { $0.requestId == "shared" }?.panelId, "a")
        XCTAssertEqual(HomeAttentionSnapshot(messages: [], questionnaires: Array(requests.reversed()),
                                            terminalPanelIDs: ["done"], now: now).questionnaires,
                       snapshot.questionnaires)
    }

    func testLatestRevisionAndServerClockControlQuestionnaireExpiry() {
        let old = request("revision", revision: 1)
        let latest = request("revision", revision: 2, expires: now.addingTimeInterval(10))
        let snapshot = HomeAttentionSnapshot(messages: [], questionnaires: [old, latest], now: now)
        XCTAssertEqual(snapshot.questionnaires.map(\.requestRevision), [2])
        let expired = HomeAttentionSnapshot(messages: [], questionnaires: [latest, old], now: now,
                                            panelNow: { _ in self.now.addingTimeInterval(10) })
        XCTAssertEqual(expired.count, 0)
    }

    func testTerminalPanelLinkCannotHideTheSameRequestOnAnActivePanel() {
        let snapshot = HomeAttentionSnapshot(messages: [], questionnaires: [
            request("shared", panel: "a-terminal"), request("shared", panel: "z-active")
        ], terminalPanelIDs: ["a-terminal"], now: now)
        XCTAssertEqual(snapshot.count, 1)
        XCTAssertEqual(snapshot.questionnaires.first?.panelId, "z-active")
    }

    func testAllClearCountRequiresBothTextReplyAndQuestionnaireResolution() {
        let pending = request("form", panel: "not-yet-loaded")
        let afterReply = HomeAttentionSnapshot(messages: [ask], withdrawn: [ask.id],
                                               questionnaires: [pending], now: now)
        XCTAssertEqual(afterReply.count, 1)
        XCTAssertTrue(afterReply.groups.isEmpty)
        let settled = HomeAttentionSnapshot(messages: [ask], withdrawn: [ask.id],
                                            questionnaires: [], now: now)
        XCTAssertEqual(settled.count, 0)
    }

    func testQuestionnaireOpensItsOwningPanelEvenOutsideSelectedWallSection() throws {
        let panels = PanelsModel(demoMode: true, autoload: false)
        let tile = try XCTUnwrap(panels.tiles.first)
        panels.section = .archived
        XCTAssertTrue(panels.visibleTiles.isEmpty)
        let snapshot = HomeAttentionSnapshot(messages: [], questionnaires: [request("form", panel: tile.id)], now: now)
        let row = try XCTUnwrap(snapshot.questionnaires.first)
        panels.open(row.panelId)
        XCTAssertEqual(panels.selectedTile?.id, tile.id)
        panels.closeDetail()
        XCTAssertNil(panels.selectedTile)
    }

    func testTextReplyRemainsWithdrawnAcrossStaleHistoryThenClearsOnResolution() async {
        let api = TextReplyAPI(messages: [ask])
        let store = InboxStore(decisionAlertsEnabled: false)
        store.start(api: api)
        defer { store.stop() }
        await store.refresh()
        XCTAssertEqual(snapshot(store).count, 1)
        let result = await store.reply("Use the staging dataset", to: ask.id)
        XCTAssertEqual(result, .sent)
        await store.refresh()
        XCTAssertEqual(api.answer, "Use the staging dataset")
        XCTAssertEqual(snapshot(store).count, 0)
        XCTAssertTrue(store.withdrawn.contains(ask.id))
        api.messages = []
        await store.refresh()
        XCTAssertTrue(store.withdrawn.isEmpty)
        XCTAssertEqual(snapshot(store).count, 0)
    }

    func testFailedTextReplyRestoresAttentionAndDoesNotHideQuestionnaires() async {
        let api = TextReplyAPI(messages: [ask])
        api.fails = true
        let store = InboxStore(decisionAlertsEnabled: false)
        store.start(api: api)
        defer { store.stop() }
        await store.refresh()
        let result = await store.reply("Try staging", to: ask.id)
        XCTAssertEqual(result, .failed)
        XCTAssertEqual(snapshot(store).count, 1)
        let mixed = HomeAttentionSnapshot(messages: store.requiredInputs, withdrawn: store.withdrawn,
                                          questionnaires: [request("form")], now: now)
        XCTAssertEqual(mixed.count, 2)
    }

    func testAlreadyResolvedResponseKeepsStillPendingOptionVisible() async {
        let option = HistoryMessage(
            id: "null-expiry-option", body: "Choose a path", direction: "agent_to_boss",
            status: "sent", priority: "normal", mode: "blocking",
            metadata: MessageMetadata(options: ["Proceed"]), createdAt: now.ISO8601Format()
        )
        let api = TextReplyAPI(messages: [option])
        api.outcome = .alreadyResolved
        let store = InboxStore(decisionAlertsEnabled: false)
        store.start(api: api)
        defer { store.stop() }
        await store.refresh()
        XCTAssertEqual(store.requiredInputs.map(\.id), [option.id])
        let result = await store.reply("Proceed", to: option.id)
        XCTAssertEqual(result, .alreadyResolved)
        XCTAssertFalse(store.withdrawn.contains(option.id))
        XCTAssertEqual(store.requiredInputs.map(\.id), [option.id])
        XCTAssertEqual(HomeAttentionSnapshot(messages: store.requiredInputs, withdrawn: store.withdrawn,
                                             questionnaires: [], now: now).count, 1)
    }

    private func snapshot(_ store: InboxStore) -> HomeAttentionSnapshot {
        HomeAttentionSnapshot(messages: store.requiredInputs, withdrawn: store.withdrawn, questionnaires: [], now: now)
    }

    private var ask: HistoryMessage {
        HistoryMessage(id: "text", body: "Which dataset should I use?", agentName: "worker",
                       direction: "agent_to_boss", status: "delivered", priority: "normal",
                       mode: "blocking", createdAt: now.ISO8601Format())
    }

    private func request(_ id: String, panel: String = "panel", revision: Int = 1,
                         blocking: Bool = true, expires: Date? = nil) -> PendingQuestionnaire {
        PendingQuestionnaire(requestId: id, panelId: panel, requestRevision: revision,
                             title: "Dataset settings", blocking: blocking,
                             expiresAt: expires?.ISO8601Format(), createdAt: now.ISO8601Format())
    }
}

private final class TextReplyAPI: BossServing, RequiredInputServing, @unchecked Sendable {
    var messages: [HistoryMessage]
    var answer: String?
    var fails = false
    var outcome: ReplyOutcome = .accepted
    private var inputContinuation: AsyncThrowingStream<RequiredInputEvent, Error>.Continuation?

    init(messages: [HistoryMessage]) { self.messages = messages }

    func fetchHistory() async throws -> [HistoryMessage] { messages }

    func fetchRequiredInputs() async throws -> [HistoryMessage] {
        messages.filter { $0.mode == "blocking" && $0.status != "replied" }
    }

    func requiredInputStream() async -> AsyncThrowingStream<RequiredInputEvent, Error> {
        AsyncThrowingStream { continuation in
            inputContinuation = continuation
            continuation.yield(.ready)
        }
    }

    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> {
        AsyncThrowingStream { $0.onTermination = { _ in } }
    }

    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func fetchMessage(_ id: MessageID) async throws -> MessageDetail {
        throw HibossAPIError.requestFailed(status: 404, message: "Missing test message")
    }

    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome {
        if fails { throw HibossAPIError.requestFailed(status: 503, message: "Unavailable") }
        if outcome == .alreadyResolved { return outcome }
        answer = choice
        return outcome
    }
}
