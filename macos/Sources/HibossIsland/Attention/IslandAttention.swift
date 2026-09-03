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
    /// Ranked attention first so the island never leads with a different item
    /// than the window. If nothing qualifies, fall back to the live interrupt.
    static func presentation(
        live: OptionMessage?,
        history: [HistoryMessage],
        now: Date
    ) -> IslandPresentation? {
        if let first = AttentionRanking.items(history: history, live: live, now: now).first {
            return IslandPresentation(message: first.asOptionMessage, item: first)
        }
        if let live {
            return IslandPresentation(message: live, item: nil)
        }
        return nil
    }

    static func autoDecisionCaption(for item: AttentionItem, now: Date) -> String? {
        guard item.isRunningAutoDecision(at: now),
              let option = item.defaultOption,
              let remaining = item.remaining(at: now) else { return nil }
        return L("Chooses \(option) in \(remaining)")
    }
}
