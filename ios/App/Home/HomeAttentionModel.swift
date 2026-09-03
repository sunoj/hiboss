// Pure attention ranking and grouping for the Home root surface.
// Exports: AttentionModel, AttentionItem, and AttentionGroup.
// Dependencies: Foundation and HibossKit HistoryMessage.

import Foundation
import HibossKit

enum AttentionGroup: Int, CaseIterable, Equatable, Hashable {
    case autoDecision
    case blocked
    case priority

    var title: String {
        switch self {
        case .autoDecision: "Decides for you soon"
        case .blocked: "Stopped on you"
        case .priority: "Priority"
        }
    }
}

struct AttentionItem: Identifiable, Equatable {
    let message: HistoryMessage
    let group: AttentionGroup

    var id: MessageID { message.id }
    var project: String? { message.project }
    var options: [String] { message.options }
    var defaultOption: String? { message.defaultOption }
    var expiresAt: Date? { message.expirationDate }
}

struct AttentionGroupItems: Equatable {
    let group: AttentionGroup
    let items: [AttentionItem]
}

enum AttentionModel {
    static func items(from messages: [HistoryMessage], now: Date = Date()) -> [AttentionItem] {
        grouped(from: messages, now: now).flatMap(\.items)
    }

    static func grouped(from messages: [HistoryMessage], now: Date = Date()) -> [AttentionGroupItems] {
        let ranked = messages.compactMap { classify($0, now: now) }.sorted(by: isMoreUrgent)
        return AttentionGroup.allCases.compactMap { group in
            let items = ranked.filter { $0.group == group }
            return items.isEmpty ? nil : AttentionGroupItems(group: group, items: items)
        }
    }

    private static func classify(_ message: HistoryMessage, now: Date) -> AttentionItem? {
        guard message.direction == "agent_to_boss",
              !message.isResolved,
              message.metadata?.isExpired != true,
              !message.options.isEmpty else { return nil }
        if let deadline = message.expirationDate, deadline <= now { return nil }

        if message.expirationDate != nil, nonEmpty(message.defaultOption) != nil {
            return AttentionItem(message: message, group: .autoDecision)
        }
        if message.expirationDate == nil, message.sessionStatus?.lowercased() == "waiting" {
            return AttentionItem(message: message, group: .blocked)
        }
        guard message.priorityValue == .critical || message.priorityValue == .high else { return nil }
        return AttentionItem(message: message, group: .priority)
    }

    private static func isMoreUrgent(_ lhs: AttentionItem, _ rhs: AttentionItem) -> Bool {
        if lhs.group.rawValue != rhs.group.rawValue {
            return lhs.group.rawValue < rhs.group.rawValue
        }
        if lhs.group == .autoDecision, lhs.expiresAt != rhs.expiresAt {
            return (lhs.expiresAt ?? .distantFuture) < (rhs.expiresAt ?? .distantFuture)
        }
        let leftPriority = lhs.message.priorityValue.rank
        let rightPriority = rhs.message.priorityValue.rank
        if leftPriority != rightPriority { return leftPriority > rightPriority }
        let leftCreated = ISOTimestamp.date(from: lhs.message.createdAt) ?? .distantFuture
        let rightCreated = ISOTimestamp.date(from: rhs.message.createdAt) ?? .distantFuture
        if leftCreated != rightCreated { return leftCreated < rightCreated }
        return lhs.id.rawValue < rhs.id.rawValue
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
