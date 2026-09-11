// Exercises overview updates through the live store when this or another client answers.
// Exports: OverviewResolutionE2ETests and a deterministic in-memory API scenario.
// Dependencies: XCTest, HibossKit OptionFlowStore, OverviewSnapshot.

import XCTest
import HibossKit
@testable import HibossIsland

@MainActor
final class OverviewResolutionE2ETests: XCTestCase {
    func testAnswerOnAnotherClientRefreshesOverviewAndCompleted() async throws {
        let api = OverviewResolutionAPI()
        let flow = OptionFlowStore()
        flow.connect(api: api)
        defer { flow.disconnect() }
        try await waitUntil { flow.historyState == .loaded && flow.connectionState == .connected }
        XCTAssertEqual(snapshot(flow).count(.needsYou), 1)

        await api.answerElsewhere()

        try await waitUntil { self.snapshot(flow).count(.completed) == 1 }
        XCTAssertEqual(snapshot(flow).count(.needsYou), 0)
        XCTAssertEqual(snapshot(flow).count(.all), 1)
    }

    func testCustomReplyMovesQuestionIntoCompleted() async throws {
        let api = OverviewResolutionAPI()
        let flow = OptionFlowStore()
        flow.connect(api: api)
        defer { flow.disconnect() }
        try await waitUntil { flow.historyState == .loaded }
        let reply = AttentionReplyState()
        reply.drafts["question"] = "Please run the smoke tests first."

        await reply.send(reply.drafts["question"] ?? "", for: "question") { text, id in
            await flow.answerHistory(text, for: id)
        }

        XCTAssertEqual(snapshot(flow).count(.completed), 1)
        XCTAssertEqual(snapshot(flow).count(.needsYou), 0)
        XCTAssertNil(reply.drafts["question"])
    }

    private func snapshot(_ flow: OptionFlowStore) -> OverviewSnapshot {
        OverviewSnapshot(history: flow.historyMessages, live: flow.activeMessage, now: AttentionTestSupport.now)
    }

    private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !predicate() {
            if ContinuousClock.now >= deadline { throw TestError.timeout }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

private actor OverviewResolutionAPI: BossServing {
    private var answered = false
    private var continuation: AsyncThrowingStream<BossEvent, Error>.Continuation?

    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func messageStream() -> AsyncThrowingStream<BossEvent, Error> {
        AsyncThrowingStream { continuation = $0 }
    }

    func fetchHistory() async throws -> [HistoryMessage] {
        [AttentionTestSupport.ask(id: "question", options: ["Ship", "Wait"],
            status: answered ? "replied" : "delivered", sessionStatus: "waiting")]
    }

    func fetchMessage(_ messageID: MessageID) async throws -> MessageDetail {
        guard let message = try await fetchHistory().first else { throw TestError.rejected }
        return MessageDetail(message: message, replies: [])
    }

    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome {
        answered = true
        return .accepted
    }

    func answerElsewhere() {
        answered = true
        continuation?.yield(.resolved(OptionResolution(id: "question", status: .replied)))
    }
}
