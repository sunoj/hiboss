// Deterministic history transport with explicit request barriers for sync tests.
// Exports HistoryTestAPI, HistoryRecorder, and historyRow fixtures to this test target.
// Depends on XCTest and HibossKit; no network or credential storage is used.

import Foundation
@testable import HibossKit

actor HistoryTestAPI: BossServing, SessionsServing {
    var pages: [HistoryResponse]
    var cursors: [String?] = []
    var blocked = false
    var gate: CheckedContinuation<Void, Never>?
    var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    let key: HistoryCacheKey?
    let identity: String?
    var eventContinuation: AsyncThrowingStream<BossEvent, Error>.Continuation?
    var queuedEvents: [BossEvent] = []
    var inventoryObserver: (@Sendable () -> Void)?

    init(_ pages: [HistoryResponse], config: ConnectionConfig? = nil, identity: String? = nil) {
        self.pages = pages
        key = config.map { HistoryCacheKey(config: $0) }
        self.identity = identity
    }

    nonisolated var historyCacheKey: HistoryCacheKey? { key }
    func fetchHistoryBossID() async throws -> String? { identity }
    func fetchHistory() async throws -> [HistoryMessage] { [] }
    func fetchMessage(_ messageID: MessageID) async throws -> MessageDetail { throw URLError(.badURL) }
    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome { .accepted }
    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream<BossEvent, Error>.makeStream()
        eventContinuation = continuation
        for event in queuedEvents { continuation.yield(event) }
        queuedEvents = []
        return stream
    }
    func sendEvent() {
        let event = BossEvent.message(OptionMessage(id: "event", body: "new note"))
        if let eventContinuation { eventContinuation.yield(event) } else { queuedEvents.append(event) }
    }
    func observeInventory(_ observer: @escaping @Sendable () -> Void) { inventoryObserver = observer }
    func projectSessions() async throws -> [ProjectSession] {
        inventoryObserver?()
        return []
    }
    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> { AsyncThrowingStream { _ in } }

    func fetchHistoryPage(updatedAfter: String?) async throws -> HistoryResponse {
        cursors.append(updatedAfter)
        let page = pages.count > 1 ? pages.removeFirst() : pages[0]
        let ready = waiters.filter { $0.0 <= cursors.count }
        waiters.removeAll { $0.0 <= cursors.count }
        for (_, waiter) in ready { waiter.resume() }
        if blocked { await withCheckedContinuation { gate = $0 } }
        return page
    }

    func blockNext() { blocked = true }
    func release() {
        blocked = false
        gate?.resume()
        gate = nil
    }

    func waitForRequests(_ count: Int) async {
        if cursors.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
}

@MainActor
final class HistoryRecorder {
    var publications: [[HistoryMessage]] = []
    var errors: [String] = []

    func receive(_ rows: [HistoryMessage]?, _ error: String?) {
        if let rows { publications.append(rows) }
        if let error { errors.append(error) }
    }
}

func historyRow(_ id: String, day: Int = 1, body: String = "note") -> HistoryMessage {
    HistoryMessage(
        id: MessageID(rawValue: id), body: body, direction: "agent_to_boss",
        status: "delivered", priority: "normal", createdAt: "2026-10-0\(day)T00:00:00Z",
        updatedAt: "2026-10-10 10:00:00"
    )
}
