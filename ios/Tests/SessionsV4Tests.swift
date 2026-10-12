// Verifies inventory omission/error states and Box author/search filters without ranking.
// Exports SessionsV4Tests; service fixtures implement the shared read-only API boundary.
// Dependencies: XCTest, HibossKit, SessionFactsStore, and BoxFilter.

import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class SessionsV4Tests: XCTestCase {
    func testUnloadedRequiredInputsDoNotFallBackToAnOlderMessage() {
        let store = InboxStore(decisionAlertsEnabled: false)
        let ordinary = replyMessage("ordinary", body: "Earlier update")
        let decision = replyMessage("decision", body: "Choose?", options: ["Yes", "No"])
        store.history = [ordinary, decision]
        let targets = SessionReplyTarget.eligible(events: replyEvents([ordinary, decision]), store: store)
        XCTAssertTrue(targets.isEmpty)
    }

    func testAnsweredIDRemainsWithdrawnAfterRequiredInputsDropIt() async {
        let store = InboxStore(decisionAlertsEnabled: false)
        store.api = ControlledInputAPI()
        let decision = replyMessage("decision", body: "Choose?", options: ["Yes", "No"])
        store.history = [decision]
        store.settleReply("Yes", for: decision.id)
        await store.refreshRequiredInputs()
        XCTAssertTrue(store.withdrawn.contains(decision.id))
        XCTAssertEqual(store.answerability(for: decision.id), .closed)
        XCTAssertEqual(store.settlement(for: decision.id)?.answer, "Yes")
    }

    func testReplyTargetLabelsDistinguishOrdinaryMessagesAndOpenDecisions() {
        let store = InboxStore(decisionAlertsEnabled: false)
        store.requiredInputLoaded = true
        let ordinary = replyMessage("ordinary", body: "First line\nSecond line")
        let decision = replyMessage("decision", body: "Which path?", options: ["A", "B"])
        store.history = [ordinary, decision]
        store.requiredInputs = [decision]
        let targets = SessionReplyTarget.eligible(events: replyEvents([ordinary, decision]), store: store)
        XCTAssertEqual(targets.map(\.label), ["Replying to: First line", "Custom answer to: Which path?"])
    }

    func testNewerMessageDoesNotRetargetDraftUntilExplicitlySelected() throws {
        let store = InboxStore(decisionAlertsEnabled: false)
        store.requiredInputLoaded = true
        let messages = [replyMessage("first", body: "First"), replyMessage("newer", body: "Newer")]
        let targets = SessionReplyTarget.eligible(events: replyEvents(messages), store: store)
        var draft = SessionReplyDraft()
        draft.update("My answer", targets: Array(targets.prefix(1)))
        XCTAssertEqual(draft.target(in: targets)?.id, "first")
        XCTAssertEqual(draft.newer(in: targets)?.id, "newer")
        draft.select(try XCTUnwrap(draft.newer(in: targets)))
        XCTAssertEqual(draft.target(in: targets)?.id, "newer")
        XCTAssertEqual(draft.text, "My answer")
        draft.update("", targets: targets)
        XCTAssertNil(draft.pinned)
        XCTAssertEqual(draft.target(in: targets)?.id, "newer")
    }

    func testResolvedDecisionCannotBeTheNewestOrPinnedTarget() {
        let store = InboxStore(decisionAlertsEnabled: false)
        store.requiredInputLoaded = true
        let ordinary = replyMessage("ordinary", body: "Update")
        let decision = replyMessage("decision", body: "Choose?", options: ["Yes", "No"])
        let events = replyEvents([ordinary, decision])
        store.history = [ordinary, decision]
        store.requiredInputs = [decision]
        var draft = SessionReplyDraft()
        draft.update("Custom answer", targets: SessionReplyTarget.eligible(events: events, store: store))
        store.requiredInputs = []
        let targets = SessionReplyTarget.eligible(events: events, store: store)
        XCTAssertEqual(targets.map(\.id), ["ordinary"])
        XCTAssertNil(draft.target(in: targets))
        XCTAssertEqual(draft.text, "Custom answer")
        XCTAssertNil(draft.newer(in: targets), "an older message must not be offered as newer")
        XCTAssertTrue(SessionReplyTarget.eligible(events: replyEvents([decision]), store: store).isEmpty)
    }

    func testUncachedResolvedDecisionMetadataCannotBecomeAReplyTarget() {
        let store = InboxStore(decisionAlertsEnabled: false)
        store.requiredInputLoaded = true
        let ordinary = replyEvents([replyMessage("ordinary", body: "Update")])
        let resolved = SessionEvent(
            id: "old-decision", sessionId: "session", sequence: 2, kind: "message",
            direction: "agent_to_boss", messageId: "missing-from-history",
            payload: .object(["body": .string("Choose?"), "options": .array([.string("Yes")])]),
            createdAt: ""
        )
        let textDecision = SessionEvent(
            id: "old-text-decision", sessionId: "session", sequence: 3, kind: "message",
            direction: "agent_to_boss", messageId: "missing-text-decision",
            payload: .object(["body": .string("Which dataset?"), "mode": .string("blocking")]),
            createdAt: ""
        )
        let targets = SessionReplyTarget.eligible(events: ordinary + [resolved, textDecision], store: store)
        XCTAssertEqual(targets.map(\.id), ["ordinary"])
    }

    func testAnswerabilityUsesOnlyLoadedTodayDecisions() {
        let store = InboxStore(decisionAlertsEnabled: false)
        let decision = replyMessage("decision", body: "Choose?", options: ["Yes", "No"])
        store.history = [decision]
        store.requiredInputs = [decision]
        XCTAssertEqual(store.answerability(for: decision.id), .checking)
        store.requiredInputLoaded = true
        XCTAssertEqual(store.answerability(for: decision.id), .open)
        XCTAssertEqual(store.todaySnapshot(now: .now).decisions.map(\.id), [decision.id])
        store.requiredInputs = []
        XCTAssertTrue(decision.isPendingDecision, "history remains open after retirement")
        XCTAssertEqual(store.answerability(for: decision.id), .closed)
        store.requiredInputs = [decision]
        store.settleReply("Yes", for: decision.id)
        store.requiredInputLoaded = false
        XCTAssertEqual(store.answerability(for: decision.id), .closed, "an outcome survives refresh")
    }

    func testRetiredAndUnloadedDecisionSubmissionsNeverReachTheServer() async {
        let decision = replyMessage("decision", body: "Choose?", options: ["Yes", "No"])
        let api = HeldReplyAPI()
        let store = InboxStore(decisionAlertsEnabled: false)
        store.api = api
        store.history = [decision]
        let checking = await store.reply("Yes", to: decision.id)
        XCTAssertEqual(checking, .failed)
        store.requiredInputLoaded = true
        let retired = await store.reply("Yes", to: decision.id)
        XCTAssertEqual(retired, .alreadyResolved)
        XCTAssertTrue(api.replies.isEmpty)
    }

    func testBoxReferenceAlsoPinsTheReplyTarget() {
        let target = SessionReplyTarget(id: "agent", sequence: 1, text: "Update", isDecision: false)
        var draft = SessionReplyDraft()
        draft.update("box:reference", targets: [target])
        XCTAssertEqual(draft.pinned, target)
    }

    private func replyMessage(_ id: MessageID, body: String, options: [String] = []) -> HistoryMessage {
        HistoryMessage(id: id, body: body, direction: "agent_to_boss", status: "delivered",
                       priority: "normal", mode: options.isEmpty ? "async" : "blocking",
                       metadata: MessageMetadata(options: options), createdAt: Date().ISO8601Format(),
                       sessionId: "session")
    }

    private func replyEvents(_ messages: [HistoryMessage]) -> [SessionEvent] {
        DemoSessionStream.events(for: "session", from: messages)
    }

    func testMissingInventoryFactsStayMissing() async {
        let model = SessionFactsStore()
        await model.load(id: "session", api: InventoryAPI(fails: false))
        XCTAssertEqual(model.session?.displayLabel, "hiboss/main")
        XCTAssertNil(model.session?.host)
        XCTAssertNil(model.session?.agentName)
        XCTAssertNil(model.session?.lastSeenAt)
        XCTAssertNil(model.session?.statusText)
        XCTAssertNil(model.error)
    }

    func testInventoryFailureKeepsEarlierFactsAndReportsError() async {
        let model = SessionFactsStore()
        await model.load(id: "session", api: InventoryAPI(fails: false))
        await model.load(id: "session", api: InventoryAPI(fails: true))
        XCTAssertEqual(model.session?.id, "session")
        XCTAssertNotNil(model.error)
    }

    func testSessionInventoryDatesAcceptServerUTCAndISOFormats() {
        let session = ProjectSession(id: "session", projectId: nil, projectSlug: nil, branch: nil,
                                     startedAt: "2026-10-09 14:15:16",
                                     lastSeenAt: "2026-10-09T14:15:16Z")
        XCTAssertNotNil(session.inventoryStartedDate)
        XCTAssertEqual(session.inventoryStartedDate, session.inventoryLastSeenDate)
        let invalid = ProjectSession(id: "session", projectId: nil, projectSlug: nil, branch: nil,
                                     startedAt: "unknown")
        XCTAssertNil(invalid.inventoryStartedDate)
        XCTAssertNil(invalid.inventoryLastSeenDate)
    }

    func testBoxAuthorFiltersNeverTreatAgentItemsAsMine() {
        let agent = BoxItem(id: "agent", bossID: "boss", bossName: "Boss", kind: .text, text: "Research",
                            createdAt: "", addedBy: .agent(id: "worker", name: "Researcher"))
        let boss = BoxItem(id: "mine", bossID: "boss", bossName: "Boss", kind: .image, text: "Reference",
                           createdAt: "")
        XCTAssertTrue(BoxFilter.all.matches(agent, search: "researcher", author: .agents))
        XCTAssertFalse(BoxFilter.all.matches(agent, search: "", author: .mine))
        XCTAssertTrue(BoxFilter.all.matches(boss, search: "reference", author: .mine))
        XCTAssertFalse(BoxFilter.all.matches(boss, search: "", author: .agents))
        XCTAssertTrue(BoxFilter.image.matches(boss, search: ""))
        XCTAssertFalse(BoxFilter.image.matches(agent, search: ""))
        XCTAssertTrue(BoxFilter.image.matches(boss, search: "", author: .mine))
        XCTAssertFalse(BoxFilter.image.matches(boss, search: "", author: .agents))
        XCTAssertFalse(BoxFilter.text.matches(agent, search: "absent", author: .agents))
    }

    func testBoxSearchMatchesNotesProjectsTagsAndLinks() {
        let item = BoxItem(id: "link", bossID: "boss", bossName: "Boss", kind: .link,
                           url: "https://example.com",
                           note: "Soil report", project: "house", tags: ["survey"], createdAt: "")
        for query in ["soil", "HOUSE", "survey", "example.com"] {
            XCTAssertTrue(BoxFilter.all.matches(item, search: query), query)
        }
        XCTAssertFalse(BoxFilter.all.matches(item, search: "absent"))
    }

    func testBoxSearchLoadsBeyondFirstPage() async {
        let model = BoxStore(api: DemoBoxAPI())
        await model.refresh()
        XCTAssertNotNil(model.nextCursor)
        XCTAssertFalse(model.items.contains { $0.id == "demo-text-20" })
        await model.loadSearchPages()
        XCTAssertNil(model.nextCursor)
        XCTAssertTrue(model.items.contains { $0.id == "demo-text-20" })
    }

    func testNewSearchFinishesPaginationWhenPreviousSearchIsCancelled() async {
        let pageStarted = expectation(description: "Second page is in flight")
        let api = SearchPagesAPI(onPageStarted: { pageStarted.fulfill() })
        let model = BoxStore(api: api)
        await model.refresh()
        let earlier = Task { await model.loadSearchPages() }
        await fulfillment(of: [pageStarted], timeout: 2)
        earlier.cancel()
        let nextStarted = expectation(description: "New search takes over")
        let latest = Task {
            nextStarted.fulfill()
            await model.loadSearchPages()
        }
        await fulfillment(of: [nextStarted], timeout: 2)
        await api.releasePage()
        await earlier.value
        await latest.value
        XCTAssertEqual(model.items.map(\.id), ["first", "second", "third"])
        XCTAssertNil(model.nextCursor)
        XCTAssertFalse(model.isLoadingMore)
    }

    func testSessionPanelsUseExactIdentityAndIgnoreAnotherScreensFilter() async {
        let model = PanelsModel(api: DemoNativePanelAPI(), demoMode: false, autoload: false)
        await model.load()
        XCTAssertEqual(model.tiles.count, 1)
        model.section = .archived
        XCTAssertEqual(SessionPanelCards(sessionID: "sess-deploy", model: model).tiles.map(\.id),
                       ["demo-panel"])
        XCTAssertTrue(SessionPanelCards(sessionID: "another-session", model: model).tiles.isEmpty)
    }

    func testExpiredDefaultKeepsDeadlineWithoutMarkingAnActiveOption() {
        let date = Date().addingTimeInterval(-60)
        let message = HistoryMessage(id: "decision", body: "Deploy?", direction: "agent_to_boss",
                                     status: "expired", priority: "normal",
                                     metadata: MessageMetadata(options: ["Yes", "No"], defaultOption: "No"),
                                     expiresAt: date.ISO8601Format(), createdAt: "")
        let timing = DecisionTiming(message: message)
        XCTAssertNotNil(timing.deadline)
        XCTAssertNil(timing.expiresAt)
        XCTAssertNil(timing.autoDefault)
        XCTAssertEqual(timing.declaredDefault, "No")
    }
}

private struct InventoryAPI: SessionsServing {
    let fails: Bool

    func projectSessions() async throws -> [ProjectSession] {
        if fails { throw HibossAPIError.invalidResponse }
        return [ProjectSession(id: "session", projectId: nil, projectSlug: "hiboss", branch: "main")]
    }
}

private actor SearchPagesAPI: BoxServing {
    let onPageStarted: @Sendable () -> Void
    private var pending: CheckedContinuation<Void, Never>?

    init(onPageStarted: @escaping @Sendable () -> Void) {
        self.onPageStarted = onPageStarted
    }

    func releasePage() {
        pending?.resume()
        pending = nil
    }

    func boxItems(filters: BoxFilters, limit: Int, cursor: String?) async throws -> BoxPage {
        if cursor == "second" {
            await withCheckedContinuation { continuation in
                pending = continuation
                onPageStarted()
            }
        }
        let id = cursor ?? "first"
        let item = BoxItem(id: id, bossID: "boss", bossName: "Owner", kind: .text,
                           text: id, createdAt: "")
        let next = cursor == nil ? "second" : (cursor == "second" ? "third" : nil)
        return BoxPage(items: [item], nextCursor: next)
    }

    func downloadBoxMedia(id: String, to destination: URL) async throws {}
    func deleteBoxItem(id: String, purge: Bool) async throws {}
}
