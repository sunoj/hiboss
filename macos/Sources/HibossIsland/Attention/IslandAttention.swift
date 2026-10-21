// Picks and filters the island's visible option using the same ranking as the window.
// Exports: IslandAttention presentation and lifetime-local skip state.
// Dependencies: Combine, Foundation, and HibossKit Today models.

import Combine
import Foundation
import HibossKit

struct IslandPresentation: Equatable {
    let message: OptionMessage
    let item: AttentionItem?
}

@MainActor
final class IslandAttention: ObservableObject {
    static let shared = IslandAttention()

    @Published private(set) var skippedMessageIDs: Set<MessageID> = []

    private init() {}

    static func skip(messageID: MessageID) {
        shared.skip(messageID: messageID)
    }

    func skip(messageID: MessageID) {
        skippedMessageIDs.insert(messageID)
    }

    /// The most intrusive surface always carries the shared queue's first decision.
    static func presentation(snapshot: TodaySnapshot) -> IslandPresentation? {
        shared.filteredPresentation(snapshot: snapshot)
    }

    private func filteredPresentation(snapshot: TodaySnapshot) -> IslandPresentation? {
        Self.presentation(snapshot: snapshot, active: nil, state: .idle, skipped: skippedMessageIDs)
    }

    static func presentation(snapshot: TodaySnapshot, active: OptionMessage?,
                             state: PresentationState) -> IslandPresentation? {
        shared.filteredPresentation(snapshot: snapshot, active: active, state: state)
    }

    func filteredPresentation(snapshot: TodaySnapshot, active: OptionMessage?,
                              state: PresentationState) -> IslandPresentation? {
        Self.presentation(snapshot: snapshot, active: active, state: state, skipped: skippedMessageIDs)
    }

    /// Pure form for publishers: `$skippedMessageIDs` emits before the property changes.
    nonisolated static func presentation(snapshot: TodaySnapshot, active: OptionMessage?,
                                         state: PresentationState,
                                         skipped: Set<MessageID>) -> IslandPresentation? {
        if case .resolved = state, let active, !skipped.contains(active.id) {
            return IslandPresentation(message: active, item: nil)
        }
        guard let first = snapshot.topDecision(skipping: skipped) else { return nil }
        return IslandPresentation(message: first.asOptionMessage, item: first)
    }

    static func autoDecisionCaption(for item: AttentionItem, now: Date) -> String? {
        guard item.isRunningAutoDecision(at: now),
              let option = item.defaultOption,
              let remaining = item.remaining(at: now) else { return nil }
        return L("Chooses \(option) in \(remaining)")
    }
}
