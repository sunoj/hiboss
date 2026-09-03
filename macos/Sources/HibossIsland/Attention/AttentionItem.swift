// Attention row derived from HistoryMessage; no new server fields.
// Exports: AttentionItem with band, project, and option helpers.
// Dependencies: Foundation, HibossKit HistoryMessage.

import Foundation
import HibossKit

struct AttentionItem: Identifiable, Equatable, Sendable {
    let message: HistoryMessage

    var id: MessageID { message.id }

    var project: String {
        nonEmpty(message.sessionLabel) ?? nonEmpty(message.sessionBranch) ?? L("Direct")
    }

    var asker: String {
        nonEmpty(message.agentName) ?? L("Agent")
    }

    var body: String { message.body }
    var content: String? { nonEmpty(message.content) }
    var defaultOption: String? { nonEmpty(message.defaultOption) }
    var expirationDate: Date? { message.expirationDate }
    var createdDate: Date? { HistoryTimestamp.date(from: message.createdAt) }

    var options: [String] {
        message.options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

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

    func band(at now: Date) -> AttentionBand? {
        guard isEligibleAsk else { return nil }
        if isRunningAutoDecision(at: now) { return .autoDecision }
        if isBlockedWithoutDeadline { return .blocked }
        if isDeclaredPriority { return .declaredPriority }
        return nil
    }

    func remaining(at now: Date) -> String? {
        guard isRunningAutoDecision(at: now), let expirationDate else { return nil }
        return AttentionClock.remaining(until: expirationDate, now: now)
    }

    func waited(at now: Date) -> String {
        guard let createdDate else { return L("Unknown") }
        return AttentionClock.elapsed(since: createdDate, now: now)
    }

    private var isEligibleAsk: Bool {
        message.metadata?.isExpired != true
            && !isResolved
            && !isFromBoss
            && hasChoices
    }

    private var isResolved: Bool {
        ["replied", "expired", "resolved"].contains(normalizedStatus)
    }

    private var isFromBoss: Bool {
        normalizedDirection == "boss_to_agent"
    }

    private var hasChoices: Bool {
        !options.isEmpty || defaultOption != nil
    }

    func isRunningAutoDecision(at now: Date) -> Bool {
        guard let expirationDate, expirationDate > now else { return false }
        return defaultOption != nil
    }

    private var isBlockedWithoutDeadline: Bool {
        message.expirationDate == nil && normalizedSession == "waiting"
    }

    private var isDeclaredPriority: Bool {
        let value = message.priority.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "critical" || value == "high"
    }

    private var normalizedStatus: String {
        message.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var normalizedDirection: String {
        message.direction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var normalizedSession: String {
        (message.sessionStatus ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private func nonEmpty(_ value: String?) -> String? {
    let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return cleaned.isEmpty ? nil : cleaned
}
