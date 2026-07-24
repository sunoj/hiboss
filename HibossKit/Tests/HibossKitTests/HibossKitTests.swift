// Smoke coverage for the shared kit: SSE decoding and the option-to-reply flow.
// Exports: HibossKitTests exercising SSEEventDecoder and OptionFlowStore.
// Dependencies: XCTest and the HibossKit public API.

import XCTest
@testable import HibossKit

final class HistoryMessageDecodingTests: XCTestCase {
    func testDecodesOptionalSessionFields() throws {
        let json = """
        {
          "id": "m1",
          "body": "Ship it?",
          "agent_name": "Build Agent",
          "direction": "agent_to_boss",
          "status": "delivered",
          "priority": "normal",
          "created_at": "2026-07-15T10:00:00Z",
          "session_id": "sess-1",
          "session_label": "feat/session-group",
          "session_branch": "feat/session-group-swift",
          "session_status": "working"
        }
        """
        let message = try JSONDecoder().decode(HistoryMessage.self, from: Data(json.utf8))
        XCTAssertEqual(message.sessionId, "sess-1")
        XCTAssertEqual(message.sessionLabel, "feat/session-group")
        XCTAssertEqual(message.sessionBranch, "feat/session-group-swift")
        XCTAssertEqual(message.sessionStatus, "working")
    }

    func testSessionFieldsDefaultToNilWhenAbsent() throws {
        let json = """
        {
          "id": "m2",
          "body": "Direct reply",
          "direction": "boss_to_agent",
          "status": "replied",
          "priority": "normal",
          "created_at": "2026-07-15T10:00:00Z"
        }
        """
        let message = try JSONDecoder().decode(HistoryMessage.self, from: Data(json.utf8))
        XCTAssertNil(message.sessionId)
        XCTAssertNil(message.sessionLabel)
        XCTAssertNil(message.sessionBranch)
        XCTAssertNil(message.sessionStatus)
    }

    func testReadsContentFromMetadata() throws {
        let json = """
        {
          "id": "m3",
          "body": "Approve retry?",
          "direction": "agent_to_boss",
          "status": "delivered",
          "priority": "normal",
          "created_at": "2026-07-15T10:00:00Z",
          "metadata": {
            "options": ["Approve", "Reject"],
            "content": "payments · retry policy"
          }
        }
        """
        let message = try JSONDecoder().decode(HistoryMessage.self, from: Data(json.utf8))
        XCTAssertEqual(message.content, "payments · retry policy")
    }
}

final class SSEDecodingTests: XCTestCase {
    func testDecodesOptionMessageEvent() {
        var decoder = SSEEventDecoder(decoder: JSONDecoder())
        _ = decoder.consume(line: "event: message")
        let event = decoder.consume(
            line: #"data: {"id":"m1","body":"Deploy?","agent_name":"o1","metadata":{"options":["Yes","No"]}}"#
        )
        guard case let .message(message)? = event else {
            return XCTFail("expected a message event")
        }
        XCTAssertEqual(message.id, "m1")
        XCTAssertEqual(message.options, ["Yes", "No"])
    }

    func testDecodesOptionMessageSessionFieldsAndContent() throws {
        let json = """
        {
          "id": "m2",
          "body": "Approve retry?",
          "agent_name": "codex",
          "metadata": {
            "options": ["Approve", "Reject"],
            "content": "payments · retry policy"
          },
          "session_label": "hiboss · feat/notif-project-forward",
          "session_branch": "feat/notif-project-forward"
        }
        """
        let decoded = try JSONDecoder().decode(OptionMessage.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.sessionLabel, "hiboss · feat/notif-project-forward")
        XCTAssertEqual(decoded.sessionBranch, "feat/notif-project-forward")
        XCTAssertEqual(decoded.content, "payments · retry policy")

        let encoded = try JSONEncoder().encode(decoded)
        let roundTripped = try JSONDecoder().decode(OptionMessage.self, from: encoded)
        XCTAssertEqual(roundTripped.sessionLabel, decoded.sessionLabel)
        XCTAssertEqual(roundTripped.sessionBranch, decoded.sessionBranch)
        XCTAssertEqual(roundTripped.content, decoded.content)
    }

    func testDecodesResolvedEvent() {
        var decoder = SSEEventDecoder(decoder: JSONDecoder())
        _ = decoder.consume(line: "event: resolved")
        let event = decoder.consume(line: #"data: {"id":"m1","status":"replied"}"#)
        guard case let .resolved(resolution)? = event else {
            return XCTFail("expected a resolved event")
        }
        XCTAssertEqual(resolution.id, "m1")
        XCTAssertEqual(resolution.status, .replied)
    }
}

final class OptionFlowStoreTests: XCTestCase {
    @MainActor
    func testChoosingReplyResolvesActiveMessage() async {
        let message = OptionMessage(
            id: "m1",
            body: "Deploy?",
            metadata: MessageMetadata(options: ["Approve", "Reject"])
        )
        let api = RecordingBossAPI(messages: [message])
        let store = OptionFlowStore(reconnectDelay: .seconds(60))
        store.connect(api: api)
        await waitFor { store.activeMessage?.id == "m1" }

        let ok = await store.choose("Approve", for: "m1")
        XCTAssertTrue(ok)
        XCTAssertNil(store.activeMessage)
        let recorded = await api.replies
        XCTAssertEqual(recorded, [Reply(id: "m1", body: "Approve")])
    }

    @MainActor
    func testResolvedEventWithdrawsActiveMessage() async {
        let message = OptionMessage(
            id: "m1",
            body: "Deploy?",
            metadata: MessageMetadata(options: ["Approve"])
        )
        let api = RecordingBossAPI(messages: [message], resolveAfterEmit: "m1")
        let store = OptionFlowStore(reconnectDelay: .seconds(60))
        store.connect(api: api)
        await waitFor { store.activeMessage == nil && store.connectionState == .connected }
    }

    @MainActor
    private func waitFor(
        timeout: TimeInterval = 2,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("condition not met within \(timeout)s")
    }
}

struct Reply: Equatable, Sendable {
    let id: MessageID
    let body: String
}

actor RecordingBossAPI: BossServing {
    private let messages: [OptionMessage]
    private let resolveAfterEmit: MessageID?
    private(set) var replies: [Reply] = []

    init(messages: [OptionMessage], resolveAfterEmit: MessageID? = nil) {
        self.messages = messages
        self.resolveAfterEmit = resolveAfterEmit
    }

    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> {
        let messages = messages
        let resolveAfterEmit = resolveAfterEmit
        return AsyncThrowingStream { continuation in
            for message in messages {
                continuation.yield(.message(message))
                if let resolveAfterEmit, resolveAfterEmit == message.id {
                    continuation.yield(.resolved(OptionResolution(id: message.id, status: .replied)))
                }
            }
            // Keep the stream open so the store stays connected.
        }
    }

    func fetchHistory() async throws -> [HistoryMessage] { [] }

    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome {
        replies.append(Reply(id: messageID, body: choice))
        return .accepted
    }
}
