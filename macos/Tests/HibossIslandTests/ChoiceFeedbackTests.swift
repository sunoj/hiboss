// Regressions for fetch recovery and accepted choices without server-list catch-up.
// Exports: ChoiceFeedbackTests with real required-input and overview stores.
// Dependencies: XCTest, Combine, HibossKit, and the macOS production stores.

import Combine
import Foundation
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class ChoiceFeedbackTests: XCTestCase {
    func testFailedAndCancelledFetchesRetryWhileStreamStaysReady() async throws {
        for error in [URLError(.cancelled), URLError(.networkConnectionLost)] {
            let api = RetryingChoiceInputs(error: error)
            let inputs = RequiredInputStore()
            inputs.connect(api)
            defer { inputs.disconnect() }
            try await waitForCondition { inputs.state.ready && inputs.state.failed }
            try await waitForCondition(timeout: .seconds(3)) { inputs.state.coverageComplete }
            XCTAssertEqual(inputs.state.messages.map(\.id), ["question"])
            let attempts = await api.attempts
            XCTAssertEqual(attempts, 2)
        }
    }

    func testAcceptedChoiceClosesBeforeListCatchesUpAndSurvivesPublisherUpdates() async throws {
        let question = AttentionTestSupport.ask(id: "question", options: ["Ship", "Hold"])
        let inputs = CurrentValueSubject<RequiredInputState, Never>(
            RequiredInputState(messages: [question], ready: true, loaded: true))
        let overview = OverviewStore()
        let flow = OptionFlowStore()
        overview.bind(flow: flow, requiredInputs: inputs.eraseToAnyPublisher())
        let reply = AttentionReplyState()
        reply.drafts[question.id] = "Ship"
        await reply.send("Ship", for: question.id) { text, id in
            await overview.answer(text, for: id) { _, _ in nil }
        }
        XCTAssertNil(reply.errors[question.id])
        XCTAssertNil(reply.drafts[question.id])
        XCTAssertEqual(overview.snapshot.answerability.state(for: question.id), .closed)
        XCTAssertTrue(overview.snapshot.today.decisions.isEmpty)
        inputs.send(RequiredInputState(messages: [question], ready: false, loaded: false))
        XCTAssertEqual(overview.snapshot.answerability.state(for: question.id), .closed)
        XCTAssertEqual(overview.snapshot.count(.completed), 1)
        let threads = MessageThread.fold(overview.snapshot.history)
        XCTAssertEqual(threads.first?.outcome, .chosen(option: "Ship", source: "macos"))
    }

    func testAcceptedChoiceReopensOnlyWhenServerListsItAgain() async throws {
        let question = AttentionTestSupport.ask(id: "question", options: ["Ship", "Hold"])
        let api = ControlledRequiredInputs(messages: [question])
        let inputs = RequiredInputStore()
        let overview = OverviewStore()
        overview.bind(flow: OptionFlowStore(), inputs: inputs)
        inputs.connect(api)
        defer { inputs.disconnect() }
        try await waitForCondition { inputs.state.coverageComplete }
        _ = await overview.answer("Ship", for: question.id) { _, _ in nil }
        XCTAssertEqual(overview.snapshot.answerability.state(for: question.id), .closed)
        await api.send(.ready)
        try await waitForCondition { inputs.state.listingVersion == 2 }
        XCTAssertEqual(overview.snapshot.answerability.state(for: question.id), .open)
        _ = await overview.answer("Hold", for: question.id) { _, _ in nil }
        await api.send(.message(question))
        try await waitForCondition { overview.snapshot.answerability.state(for: question.id) == .open }
    }

    func testSupersededFetchCannotFailOrReplaceNewerFetch() async throws {
        let question = AttentionTestSupport.ask(id: "question", options: ["Ship"])
        let api = ControlledRequiredInputs(messages: [question])
        await api.blockFetch()
        let inputs = RequiredInputStore()
        inputs.connect(api)
        defer { inputs.disconnect() }
        try await api.waitForFetch(count: 1)
        await api.replace([])
        inputs.refresh()
        try await api.waitForFetch(count: 2)
        await api.releaseFetches()
        try await waitForCondition { inputs.state.coverageComplete }
        XCTAssertTrue(inputs.state.messages.isEmpty)
        XCTAssertFalse(inputs.state.failed)
    }

    func testRecordedAnswerStaysClosedWhenListIsUnknown() {
        let answered = AttentionTestSupport.ask(id: "answered", options: ["Ship"], status: "replied")
        let stale = AttentionTestSupport.ask(id: "answered", options: ["Ship"])
        let snapshot = OverviewSnapshot(history: [answered], live: nil, now: .now,
            requiredInputs: [stale], requiredInputLoaded: false)
        XCTAssertEqual(snapshot.answerability.state(for: answered.id), .closed)
        XCTAssertTrue(snapshot.today.decisions.isEmpty)
        XCTAssertEqual(snapshot.count(.completed), 1)
    }

    func testFailedReplyKeepsDraftAndReenablesChoices() async {
        let question = AttentionTestSupport.ask(id: "question", options: ["Ship"])
        let overview = OverviewStore()
        overview.update(history: [question], live: nil, requiredInputs: [question], requiredInputLoaded: true)
        let reply = AttentionReplyState()
        reply.drafts[question.id] = "Ship"
        await reply.send("Ship", for: question.id) { text, id in
            await overview.answer(text, for: id) { _, _ in .failed("offline") }
        }
        XCTAssertEqual(reply.drafts[question.id], "Ship")
        XCTAssertEqual(reply.errors[question.id], .failed("offline"))
        XCTAssertTrue(reply.submitting.isEmpty)
        XCTAssertEqual(overview.snapshot.answerability.state(for: question.id), .open)
    }
}

private actor RetryingChoiceInputs: RequiredInputServing {
    let error: URLError
    private(set) var attempts = 0
    init(error: URLError) { self.error = error }

    func requiredInputStream() -> AsyncThrowingStream<RequiredInputEvent, Error> {
        AsyncThrowingStream { $0.yield(.ready) }
    }

    func fetchRequiredInputs() async throws -> [HistoryMessage] {
        attempts += 1
        if attempts == 1 { throw error }
        return [AttentionTestSupport.ask(id: "question", options: ["Ship", "Hold"])]
    }
}
