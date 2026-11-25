// The time window a pending decision runs in: from when it was asked to its timeout deadline.
// Exports: DecisionWindow with the remaining fraction a countdown ring draws.
// Dependencies: Foundation, AttentionItem, SessionGrouping, and TodayMessageRules.

import Foundation

public struct DecisionWindow: Equatable, Sendable {
    public let start: Date
    public let deadline: Date

    public init(start: Date, deadline: Date) {
        self.start = start
        self.deadline = deadline
    }

    /// 1 when asked, 0 at the deadline and after it; a window that never opened reads as spent.
    public func remainingFraction(at now: Date) -> Double {
        let total = deadline.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(max(deadline.timeIntervalSince(now) / total, 0), 1)
    }

    public func isLive(at now: Date) -> Bool { deadline > now }

    /// A decision's window, when it has both an ask time and a deadline.
    public init?(message: HistoryMessage) {
        guard let deadline = message.expirationDate,
              let start = TodayMessageRules.createdDate(message) else { return nil }
        self.init(start: start, deadline: deadline)
    }

    /// Per session, the window that ends first: the decision the boss loses soonest.
    static func soonest(in decisions: [AttentionItem]) -> [String: DecisionWindow] {
        var windows: [String: DecisionWindow] = [:]
        for item in decisions {
            guard let window = DecisionWindow(message: item.message) else { continue }
            let key = SessionGrouping.sessionKey(for: item.message)
            if windows[key].map({ window.deadline < $0.deadline }) ?? true { windows[key] = window }
        }
        return windows
    }
}
