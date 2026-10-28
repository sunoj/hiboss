// Internal message normalization and merging for deterministic Today projections.
// Exports: TodayMessageRules within HibossKit; no app-specific display dependencies.
// Dependencies: Foundation, HistoryMessage, and ISODate.

import Foundation

enum TodayMessageRules {
    static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    static func statusWord(_ value: String?) -> String? {
        nonEmpty(value)?.lowercased()
    }

    // These are the same terminal statuses used by the iOS attention model.
    static func isResolved(_ message: HistoryMessage) -> Bool {
        message.status == "replied" || message.status == "expired"
    }

    static func createdDate(_ message: HistoryMessage) -> Date? {
        ISODate.parse(message.createdAt)
    }

    /// Required inputs override history by ID; the last duplicate in each source wins.
    static func merge(history: [HistoryMessage], requiredInputs: [HistoryMessage]) -> [HistoryMessage] {
        var byID: [MessageID: HistoryMessage] = [:]
        byID.reserveCapacity(history.count + requiredInputs.count)
        for message in history { byID[message.id] = message }
        for message in requiredInputs { byID[message.id] = message }
        // Read the cached dates once per message, rather than once per comparison.
        let dated = byID.values.map { (message: $0, date: createdDate($0) ?? .distantPast) }
        return dated.sorted {
            $0.date == $1.date ? $0.message.id.rawValue < $1.message.id.rawValue : $0.date > $1.date
        }.map(\.message)
    }

    /// Ranked decisions from the server's open list only; the last duplicate wins.
    static func openDecisions(
        _ requiredInputs: [HistoryMessage], withdrawn: Set<MessageID>, now: Date
    ) -> [AttentionItem] {
        let unique = merge(history: [], requiredInputs: requiredInputs)
        return AttentionModel.items(from: unique.filter { !withdrawn.contains($0.id) }, now: now)
    }

    static func isRecent(_ date: Date?, window: TimeInterval, now: Date) -> Bool {
        guard let date else { return false }
        return date <= now && date >= now.addingTimeInterval(-window)
    }
}
