// Precomputed comparable key preserving the iOS decision ordering contract.
// Exports: UrgencyKey; group, auto deadline, priority, age, then message ID.
// Dependencies: Foundation, AttentionItem, and TodayMessageRules.

import Foundation

public struct UrgencyKey: Comparable, Sendable {
    public let group: Int
    public let deadline: Date
    public let priority: Int
    public let created: Date
    public let id: String

    public init(_ item: AttentionItem) {
        group = item.group.rawValue
        deadline = item.group == .autoDecision ? (item.expiresAt ?? .distantFuture) : .distantFuture
        priority = Self.priorityRank(item.message.priority)
        created = TodayMessageRules.createdDate(item.message) ?? .distantFuture
        id = item.id.rawValue
    }

    public static func < (lhs: UrgencyKey, rhs: UrgencyKey) -> Bool {
        if lhs.group != rhs.group { return lhs.group < rhs.group }
        if lhs.deadline != rhs.deadline { return lhs.deadline < rhs.deadline }
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        if lhs.created != rhs.created { return lhs.created < rhs.created }
        return lhs.id < rhs.id
    }

    private static func priorityRank(_ raw: String) -> Int {
        switch raw.lowercased() {
        case "critical": 3
        case "high": 2
        case "low": 0
        default: 1
        }
    }
}
