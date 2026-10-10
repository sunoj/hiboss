// Adapts InboxStore's connection evidence to the shared Today projection.
// Exports todaySnapshot and answerability; all ranking and session classification remain in HibossKit.
// Dependencies: InboxStore, TodaySnapshot, and TodayHealth.

import Foundation
import HibossKit

extension InboxStore {
    func answerability(for id: MessageID, now: Date = .now) -> DecisionAnswerability {
        let resolved = settlement(for: id) != nil ? withdrawn.union([id]) : withdrawn
        return DecisionAnswerability(id: id, openIDs: Set(todaySnapshot(now: now).decisions.map(\.id)),
                                    loaded: requiredInputLoaded, withdrawn: resolved)
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
