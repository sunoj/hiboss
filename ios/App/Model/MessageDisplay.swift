// View-facing helpers over the shared HistoryMessage domain model.
// Exports: display computed properties (initials, meta line, pending test).
// Dependencies: HibossKit HistoryMessage.

import Foundation
import HibossKit

extension HistoryMessage {
    var priorityValue: MessagePriority { MessagePriority(raw: priority) }

    /// Two-character avatar seed from the agent name.
    var avatarInitials: String {
        let name = (agentName ?? "agent").trimmingCharacters(in: .whitespaces)
        let parts = name.split { $0 == "-" || $0 == "_" || $0 == " " }
        if let first = parts.first, let last = parts.dropFirst().first,
           let a = first.first, let b = last.first {
            return String(a).uppercased() + String(b).lowercased()
        }
        return String(name.prefix(2)).capitalized
    }

    var displayName: String { agentName ?? "agent" }

    // `content` comes from HibossKit's HistoryMessage.content (metadata.content);
    // the Live Activity widget trims/empties it at render via LA.nonEmpty.
    var project: String? { nonEmpty(sessionLabel) ?? nonEmpty(sessionBranch) }

    /// e.g. "agent→boss · discord"
    var metaLine: String {
        let dir: String
        switch direction {
        case "agent_to_boss": dir = "agent→boss"
        case "boss_to_agent": dir = "boss→agent"
        case "agent_to_agent": dir = "agent→agent"
        default: dir = direction
        }
        if let channel, !channel.isEmpty { return "\(dir) · \(channel)" }
        return dir
    }

    var isResolved: Bool { status == "replied" || status == "expired" }

    /// Any decision from an agent that carries options — pending or already resolved.
    var isDecision: Bool { direction == "agent_to_boss" && !options.isEmpty }

    /// A live decision awaiting the boss: from an agent, has options, not resolved/expired.
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
