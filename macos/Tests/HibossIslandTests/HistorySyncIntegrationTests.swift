// Covers native history publication and account replacement in memory.
// Exports HistorySyncIntegrationTests with deterministic history responses.
// Depends on XCTest, Combine, HibossIsland, and HibossKit; no network calls.

import Combine
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class HistorySyncIntegrationTests: XCTestCase {
    func testFlowDoesNotRepublishAnIdenticalFullRefresh() async {
        let flow = OptionFlowStore()
        flow.connect(api: IncrementalFlowAPI())
        await flow.refreshHistory()
        var publications = 0
        let observation = flow.$historyMessages.dropFirst().sink { _ in publications += 1 }
        await flow.refreshHistory()
        XCTAssertEqual(flow.historyMessages.map(\.id), ["cached"])
        XCTAssertEqual(publications, 0)
        observation.cancel()
        flow.disconnect()
    }

    func testAPIReplacementDropsHistoryAndIgnoresLateOldSync() async {
        let old = ReplacementFlowAPI(id: "old")
        let current = ReplacementFlowAPI(id: "new")
        let flow = OptionFlowStore()
        flow.connect(api: old)
        await flow.refreshHistory()
        XCTAssertEqual(flow.historyMessages.map(\.id), ["old"])
        let started = expectation(description: "old history request started")
        await old.holdNextRequest(started)
        let lateFetch = Task { await flow.refreshHistory() }
        await fulfillment(of: [started], timeout: 2)
        flow.connect(api: current)
        XCTAssertTrue(flow.historyMessages.isEmpty)
        await flow.refreshHistory()
        XCTAssertEqual(flow.historyMessages.map(\.id), ["new"])
        await old.release()
        await lateFetch.value
        XCTAssertEqual(flow.historyMessages.map(\.id), ["new"])
        let cursors = await current.cursors
        XCTAssertFalse(cursors.isEmpty)
        XCTAssertNil(cursors[0])
        flow.disconnect()
    }
}

private struct IncrementalFlowAPI: BossServing {
    func fetchHistoryPage(updatedAfter: String?) async throws -> HistoryResponse {
        let row = HistoryMessage(id: "cached", body: "Cached", direction: "agent_to_boss",
            status: "delivered", priority: "normal", createdAt: "2026-10-01T00:00:00Z")
        return HistoryResponse(messages: [row], total: 1, cursor: "2026-10-10 10:20:30")
    }
    func fetchHistory() async throws -> [HistoryMessage] { [] }
    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> { AsyncThrowingStream { _ in } }
    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> { AsyncThrowingStream { _ in } }
    func fetchMessage(_ messageID: MessageID) async throws -> MessageDetail { throw URLError(.badURL) }
    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome { .accepted }
}


// Holds a response after request admission, even when its caller is canceled.
private actor ReplacementFlowAPI: BossServing {
    let id: MessageID
    var cursors: [String?] = []
    private var started: XCTestExpectation?
    private var response: CheckedContinuation<Void, Never>?

    init(id: MessageID) { self.id = id }
    func holdNextRequest(_ started: XCTestExpectation) { self.started = started }
    func release() {
        response?.resume()
        response = nil
    }
    func fetchHistoryPage(updatedAfter: String?) async throws -> HistoryResponse {
        cursors.append(updatedAfter)
        let held = started != nil
        if let started {
            self.started = nil
            await withCheckedContinuation {
                response = $0
                started.fulfill()
            }
        }
        let rowID = held ? MessageID(rawValue: id.rawValue + "-late") : id
        let row = HistoryMessage(id: rowID, body: "Fixture", direction: "agent_to_boss",
            status: "delivered", priority: "normal", createdAt: "2026-10-01T00:00:00Z")
        return HistoryResponse(messages: [row], total: 1, cursor: id.rawValue)
    }
    func fetchHistory() async throws -> [HistoryMessage] { [] }
    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> { AsyncThrowingStream { _ in } }
    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> { AsyncThrowingStream { _ in } }
    func fetchMessage(_ messageID: MessageID) async throws -> MessageDetail { throw URLError(.badURL) }
    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome { .accepted }
}
