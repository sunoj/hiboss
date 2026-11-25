// Maps the boss's open decisions and new arrivals to the USB status lamp's line commands.
// Exports: LampSignal (steady state), LampArrivals (which new agent messages flash green).
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

/// Whether a newly delivered agent message flashes green. It flashes only when it would alert
/// (quiet hours hold non-urgent ones), and only while fresh, so a feed replay after a
/// reconnect does not flash. An undated message has just been pushed.
enum LampArrivals {
    static let freshness: TimeInterval = 120

    static func flashes(_ message: HistoryMessage, preferences: BossPreferences, now: Date) -> Bool {
        guard message.direction == "agent_to_boss" else { return false }
        let alert = message.isDecision
            ? MessageAlertPolicy.decisionAlert(priority: message.priority, preferences: preferences, now: now)
            : MessageAlertPolicy.messageAlert(priority: message.priority, preferences: preferences, now: now)
        guard alert != nil else { return false }
        guard let created = HistoryTimestamp.date(from: message.createdAt) else { return true }
        return now.timeIntervalSince(created) <= freshness
    }
}
