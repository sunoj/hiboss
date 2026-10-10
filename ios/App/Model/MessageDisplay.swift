// View-facing helpers over the shared HistoryMessage domain model.
// Exports: display computed properties (initials, meta line, pending test).
// Dependencies: HibossKit HistoryMessage.

import Foundation
import HibossKit

extension HistoryMessage {
    var priorityValue: MessagePriority { MessagePriority(raw: priority) }

    /// Two-character avatar seed from the agent name.
    var avatarInitials: String {
        Self.avatarInitials(agentName: agentName)
    }

    static func avatarInitials(agentName: String?) -> String {
        let name = (agentName ?? "agent").trimmingCharacters(in: .whitespaces)
        let parts = name.split { $0 == "-" || $0 == "_" || $0 == " " }
        if let first = parts.first, let last = parts.dropFirst().first,
           let a = first.first, let b = last.first {
            return String(a).uppercased() + String(b).lowercased()
        }
        return String(name.prefix(2)).capitalized
    }

    var displayName: String { agentName ?? String(localized: "Agent") }

    // `content` comes from HibossKit's HistoryMessage.content (metadata.content);
    // the Live Activity widget trims/empties it at render via LA.nonEmpty.
    var project: String? { nonEmpty(sessionLabel) ?? nonEmpty(sessionBranch) }

    /// e.g. "agent→boss · discord"
    var metaLine: String {
        let dir: String
        switch direction {
        case "agent_to_boss": dir = String(localized: "agent→boss")
        case "boss_to_agent": dir = String(localized: "boss→agent")
        case "agent_to_agent": dir = String(localized: "agent→agent")
        default: dir = direction
        }
        if let channel, !channel.isEmpty { return "\(dir) · \(channel)" }
        return dir
    }

    var isResolved: Bool { status == "replied" || status == "expired" }

    /// A live decision awaiting the boss, using HibossKit's decision shape.
    var isPendingDecision: Bool {
        guard isDecision, !isResolved else { return false }
        if let expiration = expirationDate, expiration <= Date() { return false }
        return true
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
