// Presentation helpers for shared decisions; classification remains in HibossKit.
// Exports: AttentionItem provenance, clock, attachment, and option helpers.
// Dependencies: Foundation, HibossKit HistoryMessage.

import Foundation
import HibossKit

extension AttentionItem {
    var expirationDate: Date? { expiresAt }
    var createdDate: Date? { HistoryTimestamp.date(from: message.createdAt) }

    var projectTitle: String {
        nonEmpty(message.sessionLabel) ?? nonEmpty(message.sessionBranch) ?? L("Direct")
    }

    var asker: String {
        nonEmpty(message.agentName) ?? L("Agent")
    }

    var body: String { message.body }
    var provenance: String {
        [projectTitle, message.sessionBranch, asker].compactMap { $0 }.joined(separator: " · ")
    }
    var content: String? { nonEmpty(message.content) }
    var attachment: MessageAttachment? { message.metadata?.attachment }

    /// critical = 0, high = 1, anything else last. Only used inside the priority band.
    var priorityRank: Int {
        switch message.priority.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "critical": 0
        case "high": 1
        default: 2
        }
    }

    var asOptionMessage: OptionMessage {
        OptionMessage(
            id: message.id,
            body: message.body,
            agentName: message.agentName,
            metadata: message.metadata,
            expiresAt: message.expiresAt,
            sessionLabel: message.sessionLabel,
            sessionBranch: message.sessionBranch
        )
    }

    func remaining(at now: Date) -> String? {
        guard isRunningAutoDecision(at: now), let expirationDate else { return nil }
        return AttentionClock.remaining(until: expirationDate, now: now)
    }

    func waited(at now: Date) -> String {
        guard let createdDate else { return L("Unknown") }
        return AttentionClock.elapsed(since: createdDate, now: now)
    }

    func isRunningAutoDecision(at now: Date) -> Bool {
        guard let expirationDate, expirationDate > now else { return false }
        return defaultOption != nil
    }


}

private func nonEmpty(_ value: String?) -> String? {
    let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return cleaned.isEmpty ? nil : cleaned
}
