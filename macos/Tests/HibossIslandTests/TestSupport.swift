// Test doubles and fixtures for exercising the option flow without a live server.
// Exports: ScriptedBossAPI, RecordedReply, and OptionMessage.fixture.
// Dependencies: HibossIsland domain and service interfaces.

import Foundation
@testable import HibossIsland

struct RecordedReply: Equatable, Sendable {
    let messageID: MessageID
    let choice: String
}

enum TestError: Error, LocalizedError {
    case rejected
    case timeout

    var errorDescription: String? {
        switch self {
        case .rejected: "The reply was rejected."
        case .timeout: "The test timed out."
        }
    }
}

actor ScriptedBossAPI: BossServing {
    private var pendingEvents: [BossEvent]
    private let replyError: TestError?
    private let replyOutcome: ReplyOutcome
    private let eventInterval: Duration
    private(set) var recordedReplies: [RecordedReply] = []

    init(
        messages: [OptionMessage],
        replyError: TestError? = nil,
        replyOutcome: ReplyOutcome = .accepted,
        eventInterval: Duration = .zero
    ) {
        self.pendingEvents = messages.map(BossEvent.message)
        self.replyError = replyError
        self.replyOutcome = replyOutcome
        self.eventInterval = eventInterval
    }

    init(events: [BossEvent], eventInterval: Duration) {
        self.pendingEvents = events
        self.replyError = nil
        self.replyOutcome = .accepted
        self.eventInterval = eventInterval
    }

    func messageStream() -> AsyncThrowingStream<BossEvent, Error> {
        let events = pendingEvents
        let interval = eventInterval
        pendingEvents = []
        return AsyncThrowingStream { continuation in
            Task {
                for event in events {
                    continuation.yield(event)
                    try? await Task<Never, Never>.sleep(for: interval)
                }
                continuation.finish()
            }
        }
    }

    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome {
        if let replyError { throw replyError }
        recordedReplies.append(RecordedReply(messageID: messageID, choice: choice))
        return replyOutcome
    }
}

extension OptionMessage {
    static func fixture(
        id: MessageID,
        options: [String],
        isExpired: Bool = false,
        expiresAt: String? = nil
    ) -> OptionMessage {
        OptionMessage(
            id: id,
            body: "Choose an option",
            agentName: "Test Agent",
            metadata: MessageMetadata(options: options, isExpired: isExpired),
            expiresAt: expiresAt
        )
    }
}
