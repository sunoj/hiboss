// Test double that holds every reply until the test releases it, one slot per call, so a
// missing admission guard shows up as an extra recorded reply instead of a hung await.
// Exports: HeldReplyAPI, Pending, waitUntil. Dependencies: XCTest, HibossKit BossServing.

import Foundation
import HibossKit
import XCTest

final class HeldReplyAPI: BossServing, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    private var held: [Int: CheckedContinuation<ReplyOutcome, Error>] = [:]
    /// Results for replies released after they were recorded but before they suspended.
    private var early: [Int: Result<ReplyOutcome, Error>] = [:]
    private var cancelled: Set<Int> = []
    private var nextToken = 0
    private var releasedThrough = 0
    private let history: [HistoryMessage]
    private let detail: MessageDetail?

    init(history: [HistoryMessage] = [], detail: MessageDetail? = nil) {
        self.history = history
        self.detail = detail
    }

    /// Every choice that reached the server, in order.
    var replies: [String] { lock.withLock { recorded } }

    /// Resumes every reply recorded so far with the same result, including one recorded but
    /// not yet suspended, so a release never goes missing. Later replies stay held.
    func release(_ result: Result<ReplyOutcome, Error> = .success(.accepted)) {
        let waiting = lock.withLock { () -> [CheckedContinuation<ReplyOutcome, Error>] in
            var ready: [CheckedContinuation<ReplyOutcome, Error>] = []
            for token in stride(from: releasedThrough + 1, through: nextToken, by: 1) {
                if let continuation = held.removeValue(forKey: token) {
                    ready.append(continuation)
                } else if !cancelled.contains(token) {
                    early[token] = result
                }
            }
            releasedThrough = nextToken
            return ready
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
                let settled = lock.withLock { () -> Result<ReplyOutcome, Error>? in
                    if cancelled.contains(token) { return .failure(CancellationError()) }
                    if let result = early.removeValue(forKey: token) { return result }
                    held[token] = continuation
                    return nil
                }
                if let settled { continuation.resume(with: settled) }
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
        guard let detail else { throw HibossAPIError.requestFailed(status: 404, message: "") }
        return detail
    }
}

/// Work the test checks without awaiting it directly, so a reply that never returns fails
/// the test instead of hanging it.
@MainActor
final class Pending<Value> {
    struct NeverReturned: Error {}

    private(set) var isDone = false
    private var value: Value?
    private var task: Task<Void, Never>?

    init(_ work: @escaping @MainActor () async -> Value) {
        task = Task { @MainActor in
            value = await work()
            isDone = true
        }
    }

    /// The result within `waitUntil`'s bound; otherwise cancels the work and throws.
    func settled() async throws -> Value {
        await waitUntil { self.isDone }
        guard isDone, let value else {
            task?.cancel()
            throw NeverReturned()
        }
        return value
    }
}

/// Polls a condition for at most about two seconds; the caller asserts on it afterwards.
@MainActor
func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<1_000 where !condition() {
        try? await Task.sleep(for: .milliseconds(2))
    }
}
