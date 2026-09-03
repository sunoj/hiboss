// Pure attention ranking and grouping for the window and island.
// Exports: AttentionBand, AttentionSection, and AttentionRanking.
// Dependencies: Foundation, HibossKit HistoryMessage and OptionMessage.

import Foundation
import HibossKit

enum AttentionBand: Int, Comparable, CaseIterable, Identifiable, Sendable {
    case autoDecision = 0
    case blocked = 1
    case declaredPriority = 2

    var id: Int { rawValue }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .autoDecision: L("Decides itself")
        case .blocked: L("Waiting on you")
        case .declaredPriority: L("High priority")
        }
    }
}

struct AttentionSection: Identifiable, Equatable, Sendable {
    let band: AttentionBand
    let items: [AttentionItem]
    var id: AttentionBand { band }
}

enum AttentionRanking {
    /// History first (full fields), then a live option not yet in history.
    static func items(
        history: [HistoryMessage],
        live: OptionMessage? = nil,
        now: Date
    ) -> [AttentionItem] {
        merge(history: history, live: live)
            .map(AttentionItem.init(message:))
            .filter { $0.band(at: now) != nil }
            .sorted { lessThan($0, $1, now: now) }
    }

    static func grouped(_ items: [AttentionItem], now: Date) -> [AttentionSection] {
        AttentionBand.allCases.compactMap { band in
            let members = items.filter { $0.band(at: now) == band }
            guard !members.isEmpty else { return nil }
            return AttentionSection(band: band, items: members)
        }
    }

    /// Same first id the window lists and the island must show.
    static func frontID(
        history: [HistoryMessage],
        live: OptionMessage? = nil,
        now: Date
    ) -> MessageID? {
        items(history: history, live: live, now: now).first?.id
    }

    static func merge(history: [HistoryMessage], live: OptionMessage?) -> [HistoryMessage] {
        guard let live else { return history }
        if history.contains(where: { $0.id == live.id }) { return history }
        return history + [historyMessage(from: live)]
    }

    static func lessThan(_ a: AttentionItem, _ b: AttentionItem, now: Date) -> Bool {
        switch (a.band(at: now), b.band(at: now)) {
        case let (left?, right?) where left != right:
            return left < right
        case let (left?, right?) where left == right:
            return lessThanWithinBand(a, b, band: left)
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return a.id.rawValue < b.id.rawValue
        }
    }

    private static func lessThanWithinBand(
        _ a: AttentionItem,
        _ b: AttentionItem,
        band: AttentionBand
    ) -> Bool {
        switch band {
        case .autoDecision:
            let aExpiry = a.expirationDate ?? .distantFuture
            let bExpiry = b.expirationDate ?? .distantFuture
            if aExpiry != bExpiry { return aExpiry < bExpiry }
            return olderThenStable(a, b)
        case .blocked:
            return olderThenStable(a, b)
        case .declaredPriority:
            if a.priorityRank != b.priorityRank { return a.priorityRank < b.priorityRank }
            return olderThenStable(a, b)
        }
    }

    private static func olderThenStable(_ a: AttentionItem, _ b: AttentionItem) -> Bool {
        let aCreated = a.createdDate ?? .distantFuture
        let bCreated = b.createdDate ?? .distantFuture
        if aCreated != bCreated { return aCreated < bCreated }
        return a.id.rawValue < b.id.rawValue
    }

    /// Live SSE payloads omit priority, sessionStatus, and createdAt — do not invent them.
    static func historyMessage(from live: OptionMessage) -> HistoryMessage {
        HistoryMessage(
            id: live.id,
            body: live.body,
            agentName: live.agentName,
            direction: "agent_to_boss",
            status: "delivered",
            priority: "",
            metadata: live.metadata,
            expiresAt: live.expiresAt,
            createdAt: "",
            sessionLabel: live.sessionLabel,
            sessionBranch: live.sessionBranch
        )
    }
}
