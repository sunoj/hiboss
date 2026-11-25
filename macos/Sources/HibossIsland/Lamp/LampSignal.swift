// Maps the boss's open decisions and new arrivals to the USB status lamp's line commands.
// Exports: LampSignal (steady state), LampArrivals (one green flash per new agent message).
// Dependencies: Foundation, HibossKit AttentionItem, HistoryMessage and MessageAlertPolicy.

import Foundation
import HibossKit

enum LampSignal: Equatable {
    case off
    /// An open decision is waiting for the boss: blue, slow blink.
    case waiting
    /// An open decision expires within `expiringWindow`: red, fast blink. Wins over `waiting`.
    case expiring

    static let expiringWindow: TimeInterval = 5 * 60
    static let flashCommand = "flash 0 100 0 800"

    var command: String {
        switch self {
        case .off: "off"
        case .waiting: "show 0 0 100 blink 1000"
        case .expiring: "show 100 0 0 blink 400"
        }
    }

    /// Unloaded decisions light nothing. A decision quiet hours hold back from alerting
    /// does not light the lamp either, matching the Island's own presentation rule.
    static func signal(decisions: [AttentionItem], loaded: Bool,
                       preferences: BossPreferences, now: Date) -> LampSignal {
        guard loaded else { return .off }
        let alerting = decisions.filter {
            MessageAlertPolicy.decisionAlert(priority: $0.message.priority,
                preferences: preferences, now: now) != nil
        }
        guard !alerting.isEmpty else { return .off }
        let expiring = alerting.contains {
            guard let expiresAt = $0.expiresAt else { return false }
            let left = expiresAt.timeIntervalSince(now)
            return left > 0 && left <= expiringWindow
        }
        return expiring ? .expiring : .waiting
    }
}

/// Remembers which agent messages were already visible, so only a newly arrived one flashes.
/// A message older than `freshness` never flashes: the first history load and a message
/// paging back into view are not arrivals.
struct LampArrivals {
    static let freshness: TimeInterval = 120
    private var seen: Set<MessageID> = []

    mutating func hasArrival(in history: [HistoryMessage], now: Date) -> Bool {
        let incoming = history.filter { $0.direction == "agent_to_boss" }
        let arrived = incoming.contains { message in
            guard !seen.contains(message.id),
                  let created = HistoryTimestamp.date(from: message.createdAt) else { return false }
            return now.timeIntervalSince(created) <= Self.freshness
        }
        seen.formUnion(incoming.map(\.id))
        return arrived
    }
}
