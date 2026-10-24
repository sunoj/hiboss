// Bounds concurrent Box media downloads; queued callers leave the queue when cancelled.
// Exports BoxMediaLimiter, shared by original and thumbnail downloads.
// Dependencies: Swift concurrency only.

import Foundation

actor BoxMediaLimiter {
    private let limit: Int
    private var running = 0
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

    init(limit: Int) { self.limit = limit }

    func run<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        return try await operation()
    }

    private func acquire() async throws {
        if running < limit {
            running += 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                enqueue(id, continuation)
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func enqueue(_ id: UUID, _ continuation: CheckedContinuation<Void, Error>) {
        if Task.isCancelled {
            continuation.resume(throwing: CancellationError())
        } else {
            waiters.append((id, continuation))
        }
    }

    /// A released slot passes straight to the next waiter, so `running` never exceeds the limit.
    private func release() {
        if waiters.isEmpty { running -= 1 } else { waiters.removeFirst().continuation.resume() }
    }

    private func cancel(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
