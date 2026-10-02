// Reply outcomes end to end: accepted, already answered elsewhere (409), and retryable failure.
// Exports: ReplyOutcomeE2ETests over history composers, inline rows, and the live question.
// Dependencies: XCTest, HibossKit OptionFlowStore, AttentionReplyState, OutcomeScriptAPI.

import XCTest
import HibossKit
@testable import HibossIsland

@MainActor
final class ReplyOutcomeE2ETests: XCTestCase {

    private func connected(_ api: OutcomeScriptAPI) async throws -> OptionFlowStore {
        let flow = OptionFlowStore(reconnectDelay: .seconds(60))
        flow.connect(api: api)
        try await waitForCondition { flow.historyState == .loaded }
        return flow
    }

    func testHistoryComposerConflictKeepsDraftAndShowsRecordedAnswer() async throws {
        let api = OutcomeScriptAPI(questions: ["q"], steps: [.conflict(answer: "Wait", source: "ios")])
        let flow = try await connected(api)
        defer { flow.disconnect() }
        let reply = AttentionReplyState()
        reply.drafts["q"] = "Ship after the smoke tests"

        await reply.send(reply.drafts["q"] ?? "", for: "q", using: flow.answer)

        XCTAssertEqual(reply.drafts["q"], "Ship after the smoke tests")
        XCTAssertEqual(reply.errors["q"], .alreadyAnswered)
        XCTAssertEqual(flow.replyFeedback["q"], .alreadyAnswered)
        XCTAssertEqual(flow.historyMessages.first { $0.id == "q" }?.status, "replied")
        XCTAssertEqual(flow.historyMessages.first { $0.replyTo == "q" }?.body, "Wait")
    }

    func testFeedbackCopySeparatesAnsweredElsewhereFromRetryableFailure() {
        let answered = L("That decision was already answered elsewhere.")
        XCTAssertEqual(ReplyFeedback.alreadyAnswered.text, answered)
        XCTAssertEqual(ReplyFeedback.alreadyAnswered.choiceText, answered)
        XCTAssertEqual(ReplyFeedback.failed("x").text, L("Reply failed. Your draft is saved. Try again."))
        XCTAssertEqual(ReplyFeedback.failed("x").choiceText, L("Couldn't send your reply. Try again."))
    }

    func testAnswerHistoryReportsFalseOnConflict() async throws {
        let api = OutcomeScriptAPI(questions: ["q"], steps: [.conflictUnrecorded])
        let flow = try await connected(api)
        defer { flow.disconnect() }

        let accepted = await flow.answerHistory("Ship", for: "q")

        XCTAssertFalse(accepted)
        XCTAssertEqual(flow.replyFeedback["q"], .alreadyAnswered)
    }

    func testAcceptedReplyClearsDraftAndFeedback() async throws {
        let api = OutcomeScriptAPI(questions: ["q"], steps: [.accept])
        let flow = try await connected(api)
        defer { flow.disconnect() }
        let reply = AttentionReplyState()
        reply.drafts["q"] = "Ship it"

        await reply.send("Ship it", for: "q", using: flow.answer)

        XCTAssertNil(reply.drafts["q"])
        XCTAssertNil(reply.errors["q"])
        XCTAssertNil(flow.replyFeedback["q"])
        XCTAssertEqual(flow.historyMessages.first { $0.id == "q" }?.status, "replied")
    }

    func testFailedReplyIsRetryableAndRetrySucceeds() async throws {
        let api = OutcomeScriptAPI(questions: ["q"], steps: [.fail, .accept])
        let flow = try await connected(api)
        defer { flow.disconnect() }
        let reply = AttentionReplyState()
        reply.drafts["q"] = "Roll back first"

        await reply.send("Roll back first", for: "q", using: flow.answer)
        XCTAssertEqual(reply.drafts["q"], "Roll back first")
        XCTAssertEqual(reply.errors["q"], .failed("The reply was rejected."))
        XCTAssertEqual(flow.replyFeedback["q"], .failed("The reply was rejected."))

        await reply.send("Roll back first", for: "q", using: flow.answer)
        XCTAssertNil(reply.drafts["q"])
        XCTAssertNil(reply.errors["q"])
        XCTAssertNil(flow.replyFeedback["q"])
        let recorded = await api.recordedReplies
        XCTAssertEqual(recorded.count, 2)
    }

    func testInlineRowChoiceFeedbackStaysOnItsOwnMessage() async throws {
        let api = OutcomeScriptAPI(questions: ["a", "b"], steps: [.fail])
        let flow = try await connected(api)
        defer { flow.disconnect() }
        let reply = AttentionReplyState()
        reply.drafts["b"] = "Keep this draft"

        await reply.send("Ship", for: "a", using: flow.answer)

        XCTAssertEqual(reply.errors["a"], .failed("The reply was rejected."))
        XCTAssertNil(reply.errors["b"])
        XCTAssertEqual(reply.drafts["b"], "Keep this draft")
        XCTAssertNil(flow.replyFeedback["b"])
    }

    func testHistoryFailureDoesNotTouchTheActiveQuestion() async throws {
        let live = OptionMessage.fixture(id: "live", options: ["Ship", "Wait"])
        let api = OutcomeScriptAPI(questions: ["other"], live: [live], steps: [.fail])
        let flow = try await connected(api)
        defer { flow.disconnect() }
        try await waitForCondition { flow.activeMessage?.id == "live" }

        let accepted = await flow.answerHistory("Ship", for: "other")

        XCTAssertFalse(accepted)
        XCTAssertEqual(flow.activeMessage?.id, "live")
        XCTAssertEqual(flow.presentationState, .ready)
        XCTAssertNil(flow.replyFeedback["live"])
        XCTAssertEqual(flow.replyFeedback["other"], .failed("The reply was rejected."))
    }

    func testConflictOnQueuedQuestionKeepsTheActiveOne() async throws {
        let first = OptionMessage.fixture(id: "first", options: ["Ship"])
        let second = OptionMessage.fixture(id: "second", options: ["Ship"])
        let api = OutcomeScriptAPI(questions: [], live: [first, second], steps: [.conflictUnrecorded, .accept])
        let flow = try await connected(api)
        defer { flow.disconnect() }
        try await waitForCondition { flow.activeMessage?.id == "first" }

        _ = await flow.answerHistory("Ship", for: "second")
        XCTAssertEqual(flow.activeMessage?.id, "first")
        XCTAssertEqual(flow.presentationState, .ready)

        _ = await flow.choose("Ship", for: "first")
        XCTAssertNil(flow.activeMessage, "the conflicted question must not come back from the queue")
    }

    func testActiveChooseConflictShowsTheRecordedAnswerNotTheLocalChoice() async throws {
        let live = OptionMessage.fixture(id: "live", options: ["Ship", "Wait"])
        let api = OutcomeScriptAPI(questions: ["live"], live: [live],
                                   steps: [.conflict(answer: "Wait", source: "ios")])
        let flow = try await connected(api)
        defer { flow.disconnect() }
        try await waitForCondition { flow.activeMessage?.id == "live" }

        let accepted = await flow.choose("Ship", for: "live")

        XCTAssertFalse(accepted)
        XCTAssertEqual(flow.replyFeedback["live"], .alreadyAnswered)
        XCTAssertEqual(flow.presentationState, .resolved(answer: "Wait", source: "iOS"))
    }

    func testActiveSubmitConflictWithLaggingHistoryWithdrawsTheQuestion() async throws {
        let live = OptionMessage.fixture(id: "live", options: ["Ship"])
        let api = OutcomeScriptAPI(questions: ["live"], live: [live], steps: [.conflictUnrecorded])
        let flow = try await connected(api)
        defer { flow.disconnect() }
        try await waitForCondition { flow.activeMessage?.id == "live" }

        let accepted = await flow.submit("Hold until Monday", for: "live")

        XCTAssertFalse(accepted)
        XCTAssertNil(flow.activeMessage)
        XCTAssertEqual(flow.presentationState, .idle)
        XCTAssertEqual(flow.replyFeedback["live"], .alreadyAnswered)
    }

    func testConflictKeepsAnObservedStreamResolution() async throws {
        let live = OptionMessage.fixture(id: "live", options: ["Ship", "Wait"])
        let api = OutcomeScriptAPI(questions: ["live"], live: [live],
                                   steps: [.conflictAfterStream(answer: "Wait", source: "telegram")])
        let flow = try await connected(api)
        defer { flow.disconnect() }
        try await waitForCondition { flow.activeMessage?.id == "live" }

        let accepted = await flow.choose("Ship", for: "live")

        XCTAssertFalse(accepted)
        XCTAssertEqual(flow.activeMessage?.id, "live")
        XCTAssertEqual(flow.presentationState, .resolved(answer: "Wait", source: "Telegram"))
    }
}
