// Adapts InboxStore's connection evidence to the shared Today projection.
// Exports todaySnapshot and answerability; all ranking and session classification remain in HibossKit.
// Dependencies: InboxStore, TodaySnapshot, and TodayHealth.

import Foundation
import HibossKit

extension InboxStore {
    /// Called per row and per redraw, so it never builds the whole Today snapshot: only this
    /// message's entry in the server's open list goes through the shared ranking rule, which
    /// classifies each message on its own, so the answer equals membership in `decisions`.
    func answerability(for id: MessageID, now: Date = .now) -> DecisionAnswerability {
        let resolved = settlement(for: id) != nil ? withdrawn.union([id]) : withdrawn
        let candidate = requiredInputs.last { $0.id == id }.map { [$0] } ?? []
        let open = resolved.contains(id) ? [] : AttentionModel.items(from: candidate, now: now).map(\.id)
        return DecisionAnswerability(id: id, openIDs: Set(open), loaded: requiredInputLoaded, withdrawn: resolved)
    }

    func todaySnapshot(now: Date, coverageComplete: Bool? = nil) -> TodaySnapshot {
        let health: TodayHealth
        switch connectionState {
        case .connected: health = .live(checkedAt: historyCheckedAt ?? now)
        case .connecting: health = .connecting
        case .disconnected, .failed: health = .offline(since: now)
        }
        return TodaySnapshot(
            history: history, requiredInputs: requiredInputs, withdrawn: withdrawn, health: health,
            coverageComplete: coverageComplete ?? (hasCompleteRequiredInputs && didLoad
                && !isRefreshing && loadError == nil), now: now
        )
    }
}
