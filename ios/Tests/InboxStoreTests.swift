// InboxStore tests: settled cards stay visible and session threads include replies.
// Exports: InboxStoreTests covering reply traces without a server round-trip.
// Dependencies: XCTest, HiBoss app target, HibossKit BossServing.

import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class InboxStoreTests: XCTestCase {
    func testReplySettlesCardInPlaceAndKeepsBossReplyInSession() async {
        let api = MutableBossAPI(messages: [Self.question, Self.older])
        let store = InboxStore(reconnectDelay: .milliseconds(10), decisionAlertsEnabled: false)
        store.start(api: api)
        await store.refresh()

        XCTAssertEqual(store.pending.map(\.id), ["q1"])
        XCTAssertTrue(store.settledCards.isEmpty)

        let result = await store.reply("Approve", to: "q1")
        XCTAssertEqual(result, .sent)
        await store.refresh()

        XCTAssertTrue(store.pending.isEmpty)
        XCTAssertEqual(store.settledCards.map(\.id), ["q1"])
        let settlement = store.settlement(for: "q1")
        XCTAssertEqual(settlement?.answer, "Approve")
        XCTAssertEqual(settlement?.source, "ios")
        XCTAssertFalse(settlement?.answeredElsewhere ?? true)

        let thread = store.messages(inSession: "sess-a")
        XCTAssertEqual(thread.map(\.id), ["old", "q1", "r-q1"])
        XCTAssertEqual(thread.last?.direction, "boss_to_agent")
        XCTAssertEqual(thread.last?.replyTo, "q1")
    }

    func testHistoryReplyRendersAsSettledEvenWithoutLocalTap() async {
        let api = MutableBossAPI(messages: [Self.answered, Self.elsewhere])
        let store = InboxStore(reconnectDelay: .milliseconds(10), decisionAlertsEnabled: false)
        store.start(api: api)
        await store.refresh()

        XCTAssertTrue(store.pending.isEmpty)
        XCTAssertEqual(store.settledCards.map(\.id), ["q2"])
        let settlement = store.settlement(for: "q2")
        XCTAssertEqual(settlement?.answer, "Hold")
        XCTAssertEqual(settlement?.sourceLabel, "Telegram")
        XCTAssertEqual(settlement?.answeredElsewhere, true)
    }

    private static let question = HistoryMessage(
        id: "q1", body: "Ship it?", agentName: "agent",
        direction: "agent_to_boss", status: "delivered", priority: "high",
        channel: "api", mode: "blocking", type: "approval_request",
        metadata: MessageMetadata(options: ["Approve", "Reject"]),
        createdAt: "2026-08-14T10:00:00Z",
        sessionId: "sess-a", sessionLabel: "feat"
    )

    private static let older = HistoryMessage(
        id: "old", body: "Earlier note", agentName: "agent",
        direction: "agent_to_boss", status: "delivered", priority: "normal",
        createdAt: "2026-08-14T09:00:00Z",
        sessionId: "sess-a", sessionLabel: "feat"
    )

    private static let answered = HistoryMessage(
        id: "q2", body: "Hold the release?", agentName: "agent",
        direction: "agent_to_boss", status: "replied", priority: "normal",
        metadata: MessageMetadata(options: ["Ship", "Hold"]),
        createdAt: "2026-08-14T10:00:00Z",
        sessionId: "sess-b"
    )

    private static let elsewhere = HistoryMessage(
        id: "r-q2", body: "Hold", agentName: "agent",
        direction: "boss_to_agent", status: "sent", priority: "normal",
        replyTo: "q2", metadata: MessageMetadata(options: [], source: "telegram"),
        createdAt: "2026-08-14T10:01:00Z",
        targetSessionId: "sess-b"
    )
}

private final class MutableBossAPI: BossServing, @unchecked Sendable {
    var messages: [HistoryMessage]

    init(messages: [HistoryMessage]) { self.messages = messages }

    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> {
        AsyncThrowingStream { continuation in continuation.onTermination = { _ in } }
    }

    func fetchHistory() async throws -> [HistoryMessage] { messages }

    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return .accepted }
        let parent = messages[index]
        messages[index] = HistoryMessage(
            id: parent.id, body: parent.body, agentName: parent.agentName,
            direction: parent.direction, status: "replied", priority: parent.priority,
            channel: parent.channel, mode: parent.mode, type: parent.type,
            metadata: parent.metadata, createdAt: parent.createdAt,
            sessionId: parent.sessionId, sessionLabel: parent.sessionLabel
        )
        messages.append(HistoryMessage(
            id: MessageID(rawValue: "r-\(messageID.rawValue)"), body: choice, agentName: parent.agentName,
            direction: "boss_to_agent", status: "sent", priority: "normal",
            replyTo: messageID.rawValue, metadata: MessageMetadata(options: [], source: "ios"),
            createdAt: "2026-08-14T10:02:00Z",
            targetSessionId: parent.sessionId
        ))
        return .accepted
    }
}
