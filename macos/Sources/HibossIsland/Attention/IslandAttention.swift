// Picks the island's visible option using the same ranking as the window.
// Exports: IslandAttention.presentation.
// Dependencies: HibossKit OptionMessage and HistoryMessage, TodaySnapshot.

import Foundation
import HibossKit

struct IslandPresentation: Equatable {
    let message: OptionMessage
    let item: AttentionItem?
}

enum IslandAttention {
    /// The most intrusive surface always carries the shared queue's first decision.
    static func presentation(snapshot: TodaySnapshot) -> IslandPresentation? {
        let items = snapshot.decisions
        guard let first = items.first else { return nil }
        return IslandPresentation(message: first.asOptionMessage, item: first)
    }

    static func presentation(snapshot: TodaySnapshot, active: OptionMessage?,
                             state: PresentationState) -> IslandPresentation? {
        if case .resolved = state, let active {
            return IslandPresentation(message: active, item: nil)
        }
        return presentation(snapshot: snapshot)
    }

    static func autoDecisionCaption(for item: AttentionItem, now: Date) -> String? {
        guard item.isRunningAutoDecision(at: now),
              let option = item.defaultOption,
              let remaining = item.remaining(at: now) else { return nil }
        return L("Chooses \(option) in \(remaining)")
    }
}
