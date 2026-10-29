// Opt-in expanded History-thread costs; skipped in ordinary tiers to avoid desktop takeover.
// Exports: PerfSurveyHistoryTests, including a long thread and bound reply typing.
// Dependencies: production HistoryThreadRow and the existing session conversation fixture.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class PerfSurveyHistoryTests: XCTestCase {
    func testExpandedHistoryThread() async throws {
        try PerfSurveyMetrics.enabled()
        for count in [3, 2_000] {
            let label = "History expanded \(count)"
            guard PerfSurveyMetrics.accepts(label) else { continue }
            let seed = SessionThreadFixtures.history()
            let question = try XCTUnwrap(seed.first)
            let model = PerfSurveyHistoryModel(question: question, count: count)
            let reply = AttentionReplyState()
            let window = try PerfSurveyFixtures.window(PerfSurveyHistorySurface(model: model, reply: reply))
            defer { PerfSurveyFixtures.close(window) }
            var revision = 0
            try await PerfSurveyMetrics.measure(label, size: "1 question / \(count) replies", window: window,
                update: {
                    revision += 1
                    model.arrive("arrival-\(revision)")
                }, interact: {
                    let binding = Binding(get: { reply.drafts[question.id] ?? "" },
                        set: { reply.drafts[question.id] = $0 })
                    binding.wrappedValue = "Run focused validation."
                })
        }
    }
}

@MainActor
private final class PerfSurveyHistoryModel: ObservableObject {
    let question: HistoryMessage
    @Published var replies: [HistoryMessage]

    init(question: HistoryMessage, count: Int) {
        self.question = question
        replies = (0..<count).map { index in
            HistoryMessage(id: MessageID(rawValue: "reply-\(index)"),
                body: "Validation step \(index) passed.",
                agentName: "Build Agent", direction: "boss_to_agent", status: "sent", priority: "normal",
                replyTo: question.id.rawValue, createdAt: AttentionTestSupport.iso(.now),
                targetSessionId: question.sessionId)
        }
    }

    func arrive(_ id: String) {
        replies.append(HistoryMessage(id: MessageID(rawValue: id), body: "Review complete.",
            agentName: "Build Agent", direction: "boss_to_agent", status: "sent", priority: "normal",
            replyTo: question.id.rawValue, createdAt: AttentionTestSupport.iso(.now)))
    }
}

private struct PerfSurveyHistorySurface: View {
    @ObservedObject var model: PerfSurveyHistoryModel
    @ObservedObject var reply: AttentionReplyState

    var body: some View {
        ScrollView {
            HistoryThreadRow(thread: MessageThread(message: model.question, replies: model.replies),
                answerability: AnswerableDecisions(isLoaded: true, openIDs: [model.question.id]),
                reply: reply, isExpanded: .constant(true), isSearching: false,
                onCollapse: {}, onChoose: { _ in nil })
                .frame(maxWidth: 900).padding(24).frame(maxWidth: .infinity)
        }
    }
}
