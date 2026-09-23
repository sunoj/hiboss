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
        case .priority: "Other decisions"
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
              message.metadata?.isExpired != true else { return nil }
        if let deadline = message.expirationDate, deadline <= now { return nil }

        if message.options.isEmpty {
            return needsTextReply(message, now: now)
                ? AttentionItem(message: message, group: .blocked) : nil
        }
        if message.expirationDate != nil, nonEmpty(message.defaultOption) != nil {
            return AttentionItem(message: message, group: .autoDecision)
        }
        if message.expirationDate == nil, message.sessionStatus?.lowercased() == "waiting" {
            return AttentionItem(message: message, group: .blocked)
        }
        return AttentionItem(message: message, group: .priority)
    }

    static func needsTextReply(_ message: HistoryMessage, now: Date = Date()) -> Bool {
        message.direction == "agent_to_boss" && message.mode == "blocking"
            && message.options.isEmpty && !message.isResolved
            && message.metadata?.isExpired != true
            && (message.expirationDate.map { $0 > now } ?? true)
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

// A single projection drives Home rows, count, and the all-clear decision.
struct HomeAttentionSnapshot {
    let groups: [AttentionGroupItems]
    let questionnaires: [PendingQuestionnaire]

    var count: Int { groups.reduce(questionnaires.count) { $0 + $1.items.count } }

    init(
        messages: [HistoryMessage], withdrawn: Set<MessageID> = [],
        questionnaires: [PendingQuestionnaire], terminalPanelIDs: Set<String> = [],
        now: Date = Date(), panelNow: ((String) -> Date)? = nil
    ) {
        groups = AttentionModel.grouped(from: messages.filter { !withdrawn.contains($0.id) }, now: now)
        var seen: Set<String> = []
        let latestRevisions = questionnaires.reduce(into: [String: Int]()) { revisions, request in
            revisions[request.requestId] = max(revisions[request.requestId] ?? request.requestRevision, request.requestRevision)
        }
        self.questionnaires = questionnaires.sorted {
            if $0.requestRevision != $1.requestRevision { return $0.requestRevision > $1.requestRevision }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            if $0.requestId != $1.requestId { return $0.requestId < $1.requestId }
            return $0.panelId < $1.panelId
        }.filter { request in
            let reference = panelNow?(request.panelId) ?? now
            guard request.blocking,
                  request.requestRevision == latestRevisions[request.requestId],
                  !terminalPanelIDs.contains(request.panelId),
                  request.expiresAt.flatMap(ISOTimestamp.date(from:)).map({ $0 > reference }) ?? true else {
                return false
            }
            return seen.insert(request.requestId).inserted
        }
    }
}
