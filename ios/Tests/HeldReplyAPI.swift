// Test double that holds every reply until the test releases it, one slot per call, so a
// missing admission guard shows up as an extra recorded reply instead of a hung await.
// Exports: HeldReplyAPI, waitUntil. Dependencies: XCTest, HibossKit BossServing.

import Foundation
import HibossKit
import XCTest

final class HeldReplyAPI: BossServing, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    private var held: [Int: CheckedContinuation<ReplyOutcome, Error>] = [:]
    private var cancelled: Set<Int> = []
    private var nextToken = 0
    private let history: [HistoryMessage]

    init(history: [HistoryMessage] = []) { self.history = history }

    /// Every choice that reached the server, in order.
    var replies: [String] { lock.withLock { recorded } }

    /// Resumes every held reply with the same result.
    func release(_ result: Result<ReplyOutcome, Error> = .success(.accepted)) {
        let waiting = lock.withLock { () -> [CheckedContinuation<ReplyOutcome, Error>] in
            defer { held.removeAll() }
            return Array(held.values)
        }
        for continuation in waiting { continuation.resume(with: result) }
    }

    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome {
        let token = lock.withLock { () -> Int in
            recorded.append(choice)
            nextToken += 1
            return nextToken
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let alreadyCancelled = lock.withLock { () -> Bool in
                    if cancelled.contains(token) { return true }
                    held[token] = continuation
                    return false
                }
                if alreadyCancelled { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let continuation = lock.withLock { () -> CheckedContinuation<ReplyOutcome, Error>? in
                cancelled.insert(token)
                return held.removeValue(forKey: token)
            }
            continuation?.resume(throwing: CancellationError())
        }
    }

    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> {
        AsyncThrowingStream { continuation in continuation.onTermination = { _ in } }
    }

    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func fetchHistory() async throws -> [HistoryMessage] { history }

    func fetchMessage(_ messageID: MessageID) async throws -> MessageDetail {
        throw HibossAPIError.requestFailed(status: 404, message: "")
    }
}

/// Polls a condition for at most about two seconds; the caller asserts on it afterwards.
@MainActor
func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<1_000 where !condition() {
        try? await Task.sleep(for: .milliseconds(2))
    }
}
