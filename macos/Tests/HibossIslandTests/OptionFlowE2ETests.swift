// End-to-end tests for the complete option-message interaction flow.
// Covers: streamed message filtering, sequential presentation, and API replies.
// Dependencies: XCTest, OptionFlowStore, and ScriptedBossAPI.

import XCTest
@testable import HibossIsland

@MainActor
final class OptionFlowE2ETests: XCTestCase {
    func testDecodesProductionOptionMessageShape() throws {
        let payload = """
        {
          "id": "production-message-1",
          "body": "Choose an option",
          "agent_name": "Production Agent",
          "metadata": { "options": ["Approve", "Wait"] },
          "expires_at": "2026-07-15T07:58:00.123Z"
        }
        """

        let message = try JSONDecoder().decode(
            OptionMessage.self,
            from: Data(payload.utf8)
        )

        XCTAssertEqual(message.id, "production-message-1")
        XCTAssertEqual(message.options, ["Approve", "Wait"])
        XCTAssertNotNil(message.expirationDate)
    }

    func testDecodesGlobalResolutionImmediatelyFromSSEDataLine() {
        var decoder = SSEEventDecoder(decoder: JSONDecoder())

        XCTAssertNil(decoder.consume(line: "event: resolved"))
        let event = decoder.consume(
            line: "data: {\"id\":\"shared-message\",\"status\":\"replied\"}"
        )

        XCTAssertEqual(event, .resolved(OptionResolution(
            id: "shared-message",
            status: .replied
        )))
    }

    func testReceivesOptionsAndRepliesToEachMessageInOrder() async throws {
        let first = OptionMessage.fixture(id: "message-1", options: ["Ship", "Wait"])
        let second = OptionMessage.fixture(id: "message-2", options: ["Yes", "No"])
        let api = ScriptedBossAPI(messages: [
            .fixture(id: "ignored", options: []),
            first,
            second,
        ])
        let store = OptionFlowStore(reconnectDelay: .seconds(60))

        store.connect(api: api)
        try await waitUntil { store.activeMessage?.id == first.id }
        await store.choose("Ship")
        try await waitUntil { store.activeMessage?.id == second.id }
        await store.choose("No")

        XCTAssertNil(store.activeMessage)
        let replies = await api.recordedReplies
        XCTAssertEqual(replies, [
            RecordedReply(messageID: "message-1", choice: "Ship"),
            RecordedReply(messageID: "message-2", choice: "No"),
        ])
    }

    func testLoadsMessageHistoryWhenConnecting() async throws {
        let history = [HistoryMessage.fixture(id: "history-1", body: "Deployment complete")]
        let api = ScriptedBossAPI(messages: [], history: history)
        let store = OptionFlowStore(reconnectDelay: .seconds(60))

        store.connect(api: api)
        try await waitUntil { store.historyMessages == history }

        XCTAssertEqual(store.historyState, .loaded)
    }

    func testIgnoresExpiredAndDuplicateOptionMessages() async throws {
        let expired = OptionMessage.fixture(
            id: "expired",
            options: ["Old"],
            isExpired: true
        )
        let current = OptionMessage.fixture(id: "current", options: ["Continue"])
        let api = ScriptedBossAPI(messages: [expired, current, current])
        let store = OptionFlowStore(reconnectDelay: .seconds(60))

        store.connect(api: api)
        try await waitUntil { store.activeMessage?.id == current.id }
        await store.choose("Continue")

        XCTAssertNil(store.activeMessage)
        let replies = await api.recordedReplies
        XCTAssertEqual(replies.count, 1)
    }

    func testKeepsMessageVisibleWhenReplyFails() async throws {
        let message = OptionMessage.fixture(id: "retry", options: ["Retry"])
        let api = ScriptedBossAPI(messages: [message], replyError: TestError.rejected)
        let store = OptionFlowStore(reconnectDelay: .seconds(60))

        store.connect(api: api)
        try await waitUntil { store.activeMessage?.id == message.id }
        await store.choose("Retry")

        XCTAssertEqual(store.activeMessage?.id, message.id)
        XCTAssertEqual(store.presentationState, .failed("The reply was rejected."))
    }

    func testWithdrawsMessageResolvedByAnotherClient() async throws {
        let message = OptionMessage.fixture(id: "shared", options: ["Approve", "Wait"])
        let api = ScriptedBossAPI(
            events: [
                .message(message),
                .resolved(OptionResolution(id: message.id, status: .replied)),
            ],
            eventInterval: .milliseconds(100)
        )
        let store = OptionFlowStore(reconnectDelay: .seconds(60))

        store.connect(api: api)
        try await waitUntil { store.activeMessage?.id == message.id }
        try await waitUntil { store.activeMessage == nil }

        XCTAssertEqual(store.presentationState, .idle)
    }

    func testWithdrawsMessageAtItsExactLocalExpiry() async throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expiresAt = formatter.string(from: Date().addingTimeInterval(0.15))
        let message = OptionMessage.fixture(
            id: "expiring",
            options: ["Approve"],
            expiresAt: expiresAt
        )
        let api = ScriptedBossAPI(messages: [message])
        let store = OptionFlowStore(reconnectDelay: .seconds(60))

        store.connect(api: api)
        try await waitUntil { store.activeMessage?.id == message.id }
        try await waitUntil { store.activeMessage == nil }

        XCTAssertEqual(store.presentationState, .idle)
    }

    func testWithdrawsMessageWhenAnotherClientWinsConcurrentSelection() async throws {
        let message = OptionMessage.fixture(id: "lost-race", options: ["Approve"])
        let api = ScriptedBossAPI(messages: [message], replyOutcome: .alreadyResolved)
        let store = OptionFlowStore(reconnectDelay: .seconds(60))

        store.connect(api: api)
        try await waitUntil { store.activeMessage?.id == message.id }
        await store.choose("Approve")

        XCTAssertNil(store.activeMessage)
        XCTAssertEqual(store.presentationState, .idle)
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline { throw TestError.timeout }
            try await clock.sleep(for: .milliseconds(10))
        }
    }
}
