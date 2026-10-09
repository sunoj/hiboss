// Pure decision ranking shared by Today and intrusive decision surfaces.
// Exports: AttentionModel, AttentionItem, AttentionGroup, and AttentionGroupItems.
// Dependencies: Foundation, HistoryMessage, UrgencyKey, and TodayMessageRules.

import Foundation

public enum AttentionGroup: Int, CaseIterable, Equatable, Hashable, Sendable {
    case autoDecision
    /// An agent stopped until the boss answers, matching the session's `waiting` status.
    case waitingOnYou
    case priority
}

public struct AttentionItem: Identifiable, Equatable, Sendable {
    public let message: HistoryMessage
    public let group: AttentionGroup

    public init(message: HistoryMessage, group: AttentionGroup) {
        self.message = message
        self.group = group
    }

    public var id: MessageID { message.id }
    public var project: String? {
        TodayMessageRules.nonEmpty(message.sessionLabel) ?? TodayMessageRules.nonEmpty(message.sessionBranch)
    }
    public var options: [String] { message.options }
    public var defaultOption: String? { message.defaultOption }
    public var expiresAt: Date? { message.expirationDate }
}

public struct AttentionGroupItems: Equatable, Sendable {
    public let group: AttentionGroup
    public let items: [AttentionItem]

    public init(group: AttentionGroup, items: [AttentionItem]) {
        self.group = group
        self.items = items
    }
}

public enum AttentionModel {
    public static func items(from messages: [HistoryMessage], now: Date) -> [AttentionItem] {
        grouped(from: messages, now: now).flatMap(\.items)
    }

    public static func grouped(from messages: [HistoryMessage], now: Date) -> [AttentionGroupItems] {
        // Compute keys once so comparisons do not parse dates.
        let ranked = messages.compactMap { classify($0, now: now) }
            .map { (item: $0, key: UrgencyKey($0)) }
            .sorted { $0.key < $1.key }
            .map(\.item)
        return AttentionGroup.allCases.compactMap { group in
            let items = ranked.filter { $0.group == group }
            return items.isEmpty ? nil : AttentionGroupItems(group: group, items: items)
        }
    }

    private static func classify(_ message: HistoryMessage, now: Date) -> AttentionItem? {
        guard message.direction == "agent_to_boss",
              !TodayMessageRules.isResolved(message),
              message.metadata?.isExpired != true else { return nil }
        if let deadline = message.expirationDate, deadline <= now { return nil }

        if message.options.isEmpty {
            return needsTextReply(message, now: now)
                ? AttentionItem(message: message, group: .waitingOnYou) : nil
        }
        if message.expirationDate != nil, TodayMessageRules.nonEmpty(message.defaultOption) != nil {
            return AttentionItem(message: message, group: .autoDecision)
        }
        if message.expirationDate == nil, TodayMessageRules.statusWord(message.sessionStatus) == "waiting" {
            return AttentionItem(message: message, group: .waitingOnYou)
        }
        return AttentionItem(message: message, group: .priority)
    }

    public static func needsTextReply(_ message: HistoryMessage, now: Date) -> Bool {
        message.direction == "agent_to_boss" && message.mode == "blocking"
            && message.options.isEmpty && !TodayMessageRules.isResolved(message)
            && message.metadata?.isExpired != true
            && (message.expirationDate.map { $0 > now } ?? true)
    }
}
