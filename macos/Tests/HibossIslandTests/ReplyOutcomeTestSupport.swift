// Scripted API that injects per-call reply outcomes and records what the server then holds.
// Exports: OutcomeScriptAPI, its ReplyStep script, and the waitForCondition helper.
// Dependencies: Foundation, HibossKit BossServing, AttentionTestSupport fixtures.

import Foundation
import HibossKit
@testable import HibossIsland

/// One scripted server response to a reply attempt.
enum ReplyStep: Sendable {
    /// 200: the boss's own reply is recorded.
    case accept
    /// 409: another client already recorded `answer`; history reflects it on the next fetch.
    case conflict(answer: String, source: String)
    /// 409 while history still lags and shows the question pending.
    case conflictUnrecorded
    /// 409 after the resolution was already streamed; history still lags.
    case conflictAfterStream(answer: String, source: String)
    /// Transport or server failure.
    case fail
}

actor OutcomeScriptAPI: BossServing {
    private var steps: [ReplyStep]
    private var questions: [HistoryMessage]
    private var replies: [HistoryMessage] = []
    private let live: [OptionMessage]
    private var continuation: AsyncThrowingStream<BossEvent, Error>.Continuation?
    private(set) var recordedReplies: [RecordedReply] = []

    init(questions: [MessageID], live: [OptionMessage] = [], steps: [ReplyStep]) {
        self.questions = questions.map { AttentionTestSupport.ask(id: $0, options: ["Ship", "Wait"]) }
        self.live = live
        self.steps = steps
    }

    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func messageStream() -> AsyncThrowingStream<BossEvent, Error> {
        let pending = live
        return AsyncThrowingStream { continuation in
            self.continuation = continuation
            pending.forEach { continuation.yield(.message($0)) }
        }
    }

    func fetchHistory() async throws -> [HistoryMessage] { questions + replies }

    func fetchMessage(_ messageID: MessageID) async throws -> MessageDetail {
        guard let message = questions.first(where: { $0.id == messageID }) else { throw TestError.rejected }
        return MessageDetail(message: message, replies: replies.filter { $0.replyTo == messageID.rawValue })
    }

    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome {
        recordedReplies.append(RecordedReply(messageID: messageID, choice: choice))
        let step = steps.isEmpty ? ReplyStep.accept : steps.removeFirst()
        switch step {
        case .accept:
            record(messageID, answer: choice, source: "macos")
            return .accepted
        case let .conflict(answer, source):
            record(messageID, answer: answer, source: source)
            return .alreadyResolved
        case .conflictUnrecorded:
            return .alreadyResolved
        case let .conflictAfterStream(answer, source):
            continuation?.yield(.resolved(OptionResolution(
                id: messageID, status: .replied, answer: answer, source: source
            )))
            try? await Task.sleep(for: .milliseconds(80))
            return .alreadyResolved
        case .fail:
            throw TestError.rejected
        }
    }

    private func record(_ id: MessageID, answer: String, source: String) {
        questions = questions.map { question in
            guard question.id == id else { return question }
            return AttentionTestSupport.ask(id: id, options: question.options, status: "replied")
        }
        replies.append(HistoryMessage(
            id: MessageID(rawValue: "reply-\(id.rawValue)"), body: answer, direction: "boss_to_agent",
            status: "delivered", priority: "normal", replyTo: id.rawValue,
            metadata: MessageMetadata(options: [], source: source), createdAt: AttentionTestSupport.iso(.now)
        ))
    }
}

@MainActor
func waitForCondition(
    timeout: Duration = .seconds(2),
    _ condition: @escaping @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        if clock.now >= deadline { throw TestError.timeout }
        try await clock.sleep(for: .milliseconds(10))
    }
}
