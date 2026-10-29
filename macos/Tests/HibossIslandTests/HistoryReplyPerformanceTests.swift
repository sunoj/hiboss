// Bounds expanded History typing and arrival CPU in the normal debug suite.
// Exports: HistoryReplyPerformanceTests; contrasts editor creation with bound typing.
// Dependencies: production HistoryThreadRow, AppKit hosts, and survey CPU clocks.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class HistoryReplyPerformanceTests: XCTestCase {
    func testTypingAndArrivalStayWithinVisibleRowBudget() async throws {
        for count in [0, 3, 2_000] {
            let question = try XCTUnwrap(SessionThreadFixtures.history().first)
            let model = HistoryReplyPerformanceModel(question: question, count: count)
            let reply = AttentionReplyState()
            let window = try PerfSurveyFixtures.window(HistoryReplyPerformanceSurface(model: model, reply: reply))
            defer { PerfSurveyFixtures.close(window) }
            try await Task.sleep(for: .seconds(1))
            let reveal = try await PerfSurveyMetrics.action(window) { reply.drafts[question.id] = "R" }
            let typing = try await PerfSurveyMetrics.action(window) { reply.drafts[question.id] = "Run checks" }
            let arrival = try await PerfSurveyMetrics.action(window) { model.arrive() }
            print("History CPU \(count): reveal=\(reveal), typing=\(typing), arrival=\(arrival) ms")
            XCTAssertLessThan(typing, 40, "Bound typing must not traverse the reply list (\(count))")
            XCTAssertLessThan(arrival, 60, "Arrival must render visible rows only (\(count))")
        }
    }
}

@MainActor
private final class HistoryReplyPerformanceModel: ObservableObject {
    let question: HistoryMessage
    @Published var replies: [HistoryMessage]

    init(question: HistoryMessage, count: Int) {
        self.question = question
        replies = (0..<count).map { index in
            HistoryMessage(id: MessageID(rawValue: "reply-\(index)"), body: "Validation step \(index) passed.",
                direction: "boss_to_agent", status: "sent", priority: "normal",
                replyTo: question.id.rawValue, createdAt: AttentionTestSupport.iso(.now))
        }
    }

    func arrive() {
        replies.append(HistoryMessage(id: "arrival", body: "Review complete.", direction: "boss_to_agent",
            status: "sent", priority: "normal", replyTo: question.id.rawValue,
            createdAt: AttentionTestSupport.iso(.now)))
    }
}

private struct HistoryReplyPerformanceSurface: View {
    @ObservedObject var model: HistoryReplyPerformanceModel
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
