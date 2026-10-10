// History refresh operations retain cached rows and expose refresh progress.
// Exports InboxStore history loading helpers backed by the shared incremental sync actor.
// Dependencies: Foundation, HibossKit and required-input reconciliation.

import Foundation
import HibossKit

extension InboxStore {
    func configureHistorySync(_ api: any BossServing) {
        let version = historyVersion
        historySync = HistorySync(api: api) { [weak self] messages, error in
            guard let self, version == self.historyVersion else { return }
            if let messages {
                self.applyHistory(messages)
                await self.syncDecisionActivity()
            }
            if self.loadError != error { self.loadError = error }
            if !self.didLoad { self.didLoad = true }
            self.historyCheckedAt = .now
        }
    }

    func requestHistorySync(forceFull: Bool = false, debounced: Bool = false) {
        guard let historySync else { return }
        historyTask = Task { await historySync.synchronize(forceFull: forceFull, debounced: debounced) }
    }

    func refreshHistory() {
        requestHistorySync(forceFull: true)
        Task { await refreshRequiredInputs() }
    }

    /// Awaitable full reconciliation for pull-to-refresh.
    func refresh() async {
        guard let historySync else { return }
        let version = historyVersion
        isRefreshing = true
        defer { if version == historyVersion { isRefreshing = false } }
        async let inputRefresh: Void = refreshRequiredInputs()
        await historySync.synchronize(forceFull: true)
        await inputRefresh
    }

    /// Commit a fresh history snapshot and re-arm all derived state.
    private func applyHistory(_ messages: [HistoryMessage]) {
        history = messages
        if loadError != nil { loadError = nil }
        if !didLoad { didLoad = true }
        historyCheckedAt = .now
        adoptHistoryReplies()
        rescheduleExpiries()
    }

}
