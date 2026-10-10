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
        let inputs = RequiredInputStore()
        let overview = OverviewStore()
        overview.bind(flow: flow, inputs: inputs)
        inputs.connect(api)
        flow.connect(api: api)
        defer {
            flow.disconnect()
            inputs.disconnect()
        }
        try await waitUntil { flow.historyState == .loaded && flow.activeMessage?.id == "question"
            && inputs.state.coverageComplete }
        XCTAssertEqual(overview.snapshot.count(.needsYou), 1)

        await api.answerElsewhere()

        try await waitUntil { overview.snapshot.count(.completed) == 1 }
        XCTAssertEqual(overview.snapshot.count(.needsYou), 0)
        XCTAssertEqual(overview.snapshot.count(.all), 1)
    }

    func testCustomReplyMovesQuestionIntoCompleted() async throws {
        let api = OverviewResolutionAPI()
        let flow = OptionFlowStore()
        let inputs = RequiredInputStore()
        let overview = OverviewStore()
        overview.bind(flow: flow, inputs: inputs)
        inputs.connect(api)
        flow.connect(api: api)
        defer {
            flow.disconnect()
            inputs.disconnect()
        }
        try await waitUntil { flow.historyState == .loaded && inputs.state.coverageComplete }
        let reply = AttentionReplyState()
        reply.drafts["question"] = "Please run the smoke tests first."

        await reply.send(reply.drafts["question"] ?? "", for: "question", using: flow.answer)

        try await waitUntil { overview.snapshot.count(.completed) == 1 }
        XCTAssertEqual(overview.snapshot.count(.completed), 1)
        XCTAssertEqual(overview.snapshot.count(.needsYou), 0)
        XCTAssertNil(reply.drafts["question"])
    }

    func testAcceptedReplyStaysOpenUntilServerMembershipDrops() async throws {
        let api = OverviewResolutionAPI(resolvesReply: false)
        let inputs = RequiredInputStore()
        let flow = OptionFlowStore()
        let overview = OverviewStore()
        overview.bind(flow: flow, inputs: inputs)
        inputs.connect(api)
        flow.connect(api: api)
        defer {
            flow.disconnect()
            inputs.disconnect()
        }
        try await waitUntil { flow.historyState == .loaded && inputs.state.coverageComplete }
        let feedback = await flow.answer("Ship", for: "question")
        XCTAssertNil(feedback)
        try await waitUntil { flow.historyMessages.first?.status == "replied" }
        XCTAssertEqual(overview.snapshot.today.decisions.map(\.id), ["question"])
        await api.resolveRequiredInput()
        try await waitUntil { overview.snapshot.today.decisions.isEmpty }
        XCTAssertEqual(overview.snapshot.count(.completed), 1)
    }

    func testAcceptedChoiceShowsResolvedIslandBeforeListCatchUp() async throws {
        let api = OverviewResolutionAPI(resolvesReply: false)
        let inputs = RequiredInputStore()
        let flow = OptionFlowStore()
        let overview = OverviewStore()
        overview.bind(flow: flow, inputs: inputs)
        inputs.connect(api)
        flow.connect(api: api)
        defer {
            flow.disconnect()
            inputs.disconnect()
        }
        try await waitUntil { flow.historyState == .loaded && inputs.state.coverageComplete
            && flow.activeMessage?.id == "question" }
        let feedback = await overview.answer("Ship", for: "question", using: flow.answer)
        XCTAssertNil(feedback)
        XCTAssertEqual(overview.snapshot.answerability.state(for: "question"), .closed)
        XCTAssertTrue(overview.snapshot.today.decisions.isEmpty)
        XCTAssertEqual(MessageThread.fold(overview.snapshot.history).first?.outcome,
            .chosen(option: "Ship", source: "macos"))
        XCTAssertEqual(flow.presentationState, .resolved(answer: "Ship", source: "macos"))
        XCTAssertEqual(IslandAttention.presentation(snapshot: overview.snapshot.today,
            active: flow.activeMessage, state: flow.presentationState)?.message.id, "question")
        try await waitForCondition(timeout: .seconds(4)) { flow.activeMessage == nil }
        XCTAssertTrue(overview.snapshot.today.decisions.isEmpty)
        XCTAssertEqual(inputs.state.messages.map(\.id), ["question"])
    }

    private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !predicate() {
            if ContinuousClock.now >= deadline { throw TestError.timeout }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

private actor OverviewResolutionAPI: BossServing, RequiredInputServing {
    private let resolvesReply: Bool
    private var answered = false
    private var requiredContinuation: AsyncThrowingStream<RequiredInputEvent, Error>.Continuation?
    private var continuation: AsyncThrowingStream<BossEvent, Error>.Continuation?

    init(resolvesReply: Bool = true) { self.resolvesReply = resolvesReply }

    func resolveRequiredInput() {
        requiredContinuation?.yield(.resolved("question"))
    }

    func requiredInputStream() -> AsyncThrowingStream<RequiredInputEvent, Error> {
        AsyncThrowingStream {
            requiredContinuation = $0
            $0.yield(.ready)
        }
    }

    func fetchRequiredInputs() async throws -> [HistoryMessage] {
        answered ? [] : try await fetchHistory()
    }

    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func messageStream() -> AsyncThrowingStream<BossEvent, Error> {
        AsyncThrowingStream {
            continuation = $0
            $0.yield(.message(OptionMessage(id: "question", body: "Needs a decision",
                metadata: MessageMetadata(options: ["Ship", "Wait"]))))
        }
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
        if resolvesReply { resolveRequiredInput() }
        return .accepted
    }

    func answerElsewhere() {
        answered = true
        requiredContinuation?.yield(.resolved("question"))
        continuation?.yield(.resolved(OptionResolution(id: "question", status: .replied)))
    }
}
