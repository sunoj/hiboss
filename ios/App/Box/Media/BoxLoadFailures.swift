// Failed Box media loads with exponential backoff, so a reappearing row retries without hammering.
// Exports BoxLoadFailures for the original and thumbnail paths of BoxMediaStore.
// Dependencies: Foundation and HibossKit.

import Foundation
import HibossKit

struct BoxLoadFailures {
    static let delays: [TimeInterval] = [1, 2, 4, 8, 16, 32, 60]
    private var entries: [String: (attempts: Int, retryAt: Date)] = [:]

    mutating func record(_ item: BoxItem, now: Date) {
        let attempts = (entries[item.id]?.attempts ?? 0) + 1
        let delay = Self.delays[min(attempts, Self.delays.count) - 1]
        entries[item.id] = (attempts, now.addingTimeInterval(delay))
    }

    func canRetry(_ id: String, now: Date) -> Bool {
        entries[id].map { now >= $0.retryAt } ?? true
    }

    func retryAt(_ id: String) -> Date? { entries[id]?.retryAt }

    mutating func clear(_ id: String) { entries[id] = nil }
}
