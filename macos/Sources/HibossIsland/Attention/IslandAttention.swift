// Picks the island's visible option using the same ranking as the window.
// Exports: IslandAttention.presentation.
// Dependencies: HibossKit OptionMessage and HistoryMessage, AttentionRanking.

import Foundation
import HibossKit

struct IslandPresentation: Equatable {
    let message: OptionMessage
    let item: AttentionItem?
}

enum IslandAttention {
    /// Share the window queue, including ordinary live questions and exact expiry. An urgent
    /// band leads as in the window; among ordinary questions the live interrupt keeps the
    /// island, so an older pending question never takes over its reply field and draft.
    static func presentation(
        live: OptionMessage?,
        history: [HistoryMessage],
        now: Date
    ) -> IslandPresentation? {
        let items = AttentionRanking.items(history: history, live: live, now: now)
        guard let first = items.first else { return nil }
        if first.band(at: now) == .question, let live,
           let current = items.first(where: { $0.id == live.id }) {
            return IslandPresentation(message: current.asOptionMessage, item: current)
        }
        return IslandPresentation(message: first.asOptionMessage, item: first)
    }

    static func autoDecisionCaption(for item: AttentionItem, now: Date) -> String? {
        guard item.isRunningAutoDecision(at: now),
              let option = item.defaultOption,
              let remaining = item.remaining(at: now) else { return nil }
        return L("Chooses \(option) in \(remaining)")
    }
}
