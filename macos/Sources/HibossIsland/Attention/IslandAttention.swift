// Picks the island's visible option using the same ranking as the window.
// Exports: IslandAttention.presentation.
// Dependencies: HibossKit OptionMessage and HistoryMessage, TodayProjection.

import Foundation
import HibossKit

struct IslandPresentation: Equatable {
    let message: OptionMessage
    let item: AttentionItem?
}

enum IslandAttention {
    /// The most intrusive surface always carries the shared queue's first decision.
    static func presentation(
        live: OptionMessage?,
        history: [HistoryMessage],
        now: Date, withdrawn: Set<MessageID> = []
    ) -> IslandPresentation? {
        let items = TodayProjection.decisions(history: history, live: live, now: now, withdrawn: withdrawn)
        guard let first = items.first else { return nil }
        return IslandPresentation(message: first.asOptionMessage, item: first)
    }

}
