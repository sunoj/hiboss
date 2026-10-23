// Verifies a shown ask that closed while the stream was down leaves on the next reconnect.
// Exports OptionReconnectTests; the stream replays nothing and history never holds the ask.
// Depends on OptionFlowStore and a scripted two-cycle BossServing double.

import XCTest
@testable import HibossKit

@MainActor
final class OptionReconnectTests: XCTestCase {
    func testAskExpiredWhileOfflineLeavesOnReconnect() async throws {
        let api = ReconnectAPI(statuses: ["old": "expired", "queued": "expired"])
        let flow = OptionFlowStore(reconnectDelay: .milliseconds(10))
        flow.connect(api: api)
        defer { flow.disconnect() }
        try await waitUntil { await api.cycles >= 2 }
        try await waitUntil { flow.activeMessage == nil }
        XCTAssertEqual(flow.presentationState, .idle)
    }

    func testAskRepliedElsewhereWhileOfflineShowsItsAnswer() async throws {
        let api = ReconnectAPI(statuses: ["old": "replied", "queued": "read"])
        let flow = OptionFlowStore(reconnectDelay: .milliseconds(10))
        flow.connect(api: api)
        defer { flow.disconnect() }
        try await waitUntil { flow.presentationState == .resolved(answer: "Ship", source: "iOS") }
        XCTAssertEqual(flow.activeMessage?.id, "old")
        try await waitUntil { flow.activeMessage?.id == "queued" }
    }

    func testOpenOrUnreachableAskStaysAfterReconnect() async throws {
        let api = ReconnectAPI(statuses: ["old": "read"])
        let flow = OptionFlowStore(reconnectDelay: .milliseconds(10))
        flow.connect(api: api)
        defer { flow.disconnect() }
        try await waitUntil { await api.lookups.count >= 2 }
        XCTAssertEqual(flow.activeMessage?.id, "old")
        XCTAssertEqual(flow.presentationState, .ready)
    }

    func testDetailPastItsDeadlineCountsAsClosed() {
        let detail = MessageDetail(message: HistoryMessage(
            id: "old", body: "Deploy?", direction: "agent_to_boss", status: "read", priority: "normal",
            expiresAt: "2026-10-01T00:00:00Z", createdAt: "2026-10-01T00:00:00Z"), replies: [])
        XCTAssertEqual(OptionFlowStore.closedResolution(detail)?.status, .expired)
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(6)
        while !(await condition()) {
            if ContinuousClock.now >= deadline { throw ReconnectTestError.timeout }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private enum ReconnectTestError: Error {
    case timeout
}

/// Cycle 1 delivers two open asks and ends; later cycles deliver nothing, as after the
/// server's ten-minute replay window. History is empty, as when the asks fell out of it.
private actor ReconnectAPI: BossServing {
    private let statuses: [String: String]
    private(set) var cycles = 0
    private(set) var lookups: [MessageID] = []

    init(statuses: [String: String]) { self.statuses = statuses }

    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> {
        cycles += 1
        let first = cycles == 1
        return AsyncThrowingStream { continuation in
            guard first else { return }
            for id in ["old", "queued"] {
                continuation.yield(.message(OptionMessage(id: MessageID(rawValue: id), body: "Deploy?",
                    metadata: MessageMetadata(options: ["Ship", "Wait"]),
                    expiresAt: "2099-01-01T00:00:00Z")))
            }
            continuation.finish()
        }
    }

    func fetchHistory() async throws -> [HistoryMessage] { [] }

    func fetchMessage(_ messageID: MessageID) async throws -> MessageDetail {
        lookups.append(messageID)
        guard let status = statuses[messageID.rawValue] else {
            throw HibossAPIError.requestFailed(status: 503, message: "")
        }
        let message = HistoryMessage(id: messageID, body: "Deploy?", direction: "agent_to_boss",
            status: status, priority: "normal", metadata: MessageMetadata(options: ["Ship", "Wait"]),
            expiresAt: "2099-01-01T00:00:00Z", createdAt: "2026-10-20T00:00:00Z")
        let reply = HistoryMessage(id: MessageID(rawValue: "reply-\(messageID.rawValue)"), body: "Ship", direction: "boss_to_agent",
            status: "delivered", priority: "normal", replyTo: messageID.rawValue,
            metadata: MessageMetadata(options: [], source: "ios"), createdAt: "2026-10-20T00:01:00Z")
        return MessageDetail(message: message, replies: status == "replied" ? [reply] : [])
    }

    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome { .accepted }
}
