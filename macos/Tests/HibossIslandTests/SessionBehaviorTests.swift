// Verifies session reply scope, shared ordering, missing facts, and recorded outcomes.
// Exports: SessionBehaviorTests with API-backed drafts and panel isolation checks.
// Dependencies: XCTest, HibossKit, ScriptedBossAPI, and native session components.

import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class SessionBehaviorTests: XCTestCase {
    func testReplyTargetsNewestAgentMessageDespiteNewerBossAndPeerMessages() async throws {
        let history = [message("old", at: -100), message("new", at: -20),
            message("boss", at: -10, direction: "boss_to_agent"),
            message("peer", at: 0, session: "peer")]
        let api = ScriptedBossAPI(messages: [], history: history)
        let flow = OptionFlowStore()
        flow.connect(api: api)
        defer { flow.disconnect() }
        try await waitForCondition { flow.historyState == .loaded }
        let context = context(history: flow.historyMessages)
        let target = try XCTUnwrap(context.newestAgentMessage)
        XCTAssertEqual(target.id, "new")
        let reply = AttentionReplyState()
        reply.drafts["new"] = "  Please investigate the attachment.  "
        reply.drafts["old"] = "Keep the older draft"
        await reply.send(reply.drafts[target.id] ?? "", for: target.id, using: flow.answer)
        let receipts = await api.recordedReplies
        XCTAssertEqual(receipts,
            [RecordedReply(messageID: "new", choice: "Please investigate the attachment.")])
        XCTAssertNil(reply.drafts["new"])
        XCTAssertEqual(reply.drafts["old"], "Keep the older draft")
    }

    func testReplyFailureKeepsTheSessionDraftAndAcceptedRetryClearsIt() async {
        let reply = AttentionReplyState()
        let flow = OptionFlowStore()
        let rejected = ScriptedBossAPI(messages: [], replyError: .rejected)
        flow.connect(api: rejected)
        reply.drafts["new"] = "Review first"
        await reply.send("Review first", for: "new", using: flow.answer)
        XCTAssertEqual(reply.drafts["new"], "Review first")
        XCTAssertNotNil(reply.errors["new"])
        flow.disconnect()
        let accepted = ScriptedBossAPI(messages: [])
        flow.connect(api: accepted)
        defer { flow.disconnect() }
        await reply.send("Review first", for: "new", using: flow.answer)
        XCTAssertNil(reply.drafts["new"])
        XCTAssertNil(reply.errors["new"])
    }

    func testMissingFactsAndNoAgentMessageProduceNoInventedTargetOrProject() {
        let empty = context(history: [message("boss", direction: "boss_to_agent")])
        XCTAssertNil(empty.newestAgentMessage)
        XCTAssertNil(empty.facts)
        XCTAssertNil(empty.project)
        XCTAssertTrue(empty.peers.isEmpty)
        let partial = context(history: [], inventory: [session("session")])
        XCTAssertNil(partial.facts?.host)
        XCTAssertNil(partial.facts?.startedAt)
        XCTAssertNil(partial.facts?.agentName)
    }

    func testWaitingDecisionsAreTheSharedQueueFilteredBySessionWithoutReranking() {
        let history = [message("first", options: ["Ship"]),
            message("other", session: "peer", options: ["Wait"]),
            message("deadline", options: ["Hold"], deadline: Date.now.addingTimeInterval(100))]
        let value = context(history: history, requiredInputs: history)
        XCTAssertEqual(value.decisions, value.snapshot.today.decisions.filter {
            SessionGrouping.sessionKey(for: $0.message) == "session"
        })
        XCTAssertEqual(Set(value.decisions.map(\.id)), ["first", "deadline"])
    }

    func testPeersUseProjectIdentityAndExcludeSelfAndUnrelatedProjects() {
        let inventory = [session("session", project: "hiboss", projectID: "one"),
            session("peer", project: "renamed", projectID: "one"),
            session("other", project: "hiboss", projectID: "two")]
        let value = context(history: [], inventory: inventory)
        XCTAssertEqual(value.project, "hiboss")
        XCTAssertEqual(value.peers.map(\.id), ["peer"])
        let slugOnly = context(history: [], inventory: [session("session", project: "hiboss"),
            session("peer", project: "hiboss"), session("other", project: "elsewhere")])
        XCTAssertEqual(slugOnly.peers.map(\.id), ["peer"])
    }

    func testTimeoutBannerNeverClaimsABossChoiceOrApproval() {
        XCTAssertEqual(ResolvedBanner.title(for: .autoSelected(option: "Hold")),
            L("Default picked · not approval"))
        XCTAssertEqual(ResolvedBanner.title(for: .chosen(option: "Ship", source: "ios")),
            L("You chose \("Ship")"))
        XCTAssertEqual(ResolvedBanner.title(for: .expired), L("Expired without an answer"))
        XCTAssertNil(ResolvedBanner.title(for: .none))
        XCTAssertNil(ResolvedBanner.title(for: .open))
    }

    func testResolvedDecisionWithNoReplyReceiptDoesNotInventABossChoice() {
        let settled = HistoryMessage(id: "closed", body: "Ship?", agentName: "Agent",
            direction: "agent_to_boss", status: "replied", priority: "normal",
            metadata: MessageMetadata(options: ["Ship", "Hold"]), createdAt: "")
        XCTAssertEqual(ResolvedBanner.title(for: .none, message: settled),
            L("Resolved · answer unavailable"))
        let defaultOnly = HistoryMessage(id: "default", body: "Continue?", agentName: "Agent",
            direction: "agent_to_boss", status: "expired", priority: "normal",
            metadata: MessageMetadata(options: [], isExpired: true, defaultOption: "Hold"), createdAt: "")
        XCTAssertEqual(ResolvedBanner.title(for: .none, message: defaultOnly),
            L("Default picked · not approval"))
    }

    func testSessionPanelsUseExactSessionIDsAndProgressKeepsAllPanels() async throws {
        let model = PanelsModel(api: try StubPanelsService(populated: true), demoMode: false, autoload: false)
        await model.load()
        XCTAssertEqual(model.tiles.count, 1)
        XCTAssertEqual(PanelWall.scopedTiles(model.tiles, sessionID: "session_1").map(\.id), ["panel_1"])
        XCTAssertTrue(PanelWall.scopedTiles(model.tiles, sessionID: "another").isEmpty)
        XCTAssertEqual(PanelWall.scopedTiles(model.tiles, sessionID: nil).map(\.id), ["panel_1"])
        let fixture = try XCTUnwrap(PanelFixtures.load().all.first { $0.name == "bound-chart.json" })
        XCTAssertEqual(PanelDashboardContent(fixture: fixture, state: fixture.initialState).series?.values,
            [12, nil, 18])
    }

    private func context(history: [HistoryMessage], inventory: [ProjectSession] = [],
                         requiredInputs: [HistoryMessage] = []) -> SessionContext {
        SessionContext(id: "session", snapshot: OverviewSnapshot(history: history, live: nil, now: .now,
            requiredInputs: requiredInputs),
            inventory: inventory)
    }

    private func session(_ id: String, project: String? = nil, projectID: String? = nil) -> ProjectSession {
        ProjectSession(id: id, projectId: projectID, projectSlug: project, branch: nil)
    }

    private func message(
        _ id: MessageID, at seconds: TimeInterval = 0, session: String = "session",
        direction: String = "agent_to_boss", options: [String] = [], deadline: Date? = nil
    ) -> HistoryMessage {
        HistoryMessage(id: id, body: id.rawValue, agentName: "Agent", direction: direction,
            status: "delivered", priority: "normal", metadata: MessageMetadata(options: options,
                defaultOption: deadline == nil ? nil : "Hold"),
            expiresAt: deadline.map(AttentionTestSupport.iso),
            createdAt: AttentionTestSupport.iso(Date.now.addingTimeInterval(seconds)), sessionId: session)
    }
}
