// History refresh operations retain cached rows and expose refresh progress.
// Exports InboxStore history loading helpers with generation-based stale-result rejection.
// Dependencies: Foundation, HibossKit and required-input reconciliation.

import Foundation
import HibossKit

extension InboxStore {
    func refreshHistory() {
        guard let api else { return }
        historyTask?.cancel()
        historyVersion += 1
        let version = historyVersion
        isRefreshing = true
        historyTask = Task { [weak self] in
            defer {
                if let self, version == self.historyVersion { self.isRefreshing = false }
            }
            do {
                let messages = try await api.fetchHistory()
                guard !Task.isCancelled, let self, version == self.historyVersion else { return }
                self.applyHistory(messages)
                await self.syncDecisionActivity()
            } catch where Task.isCancelled {
                return
            } catch {
                guard let self, version == self.historyVersion else { return }
                self.loadError = error.localizedDescription
                self.didLoad = true
            }
        }
        Task { await refreshRequiredInputs() }
    }

    /// Awaitable history reload for pull-to-refresh; keeps the spinner up until done.
    func refresh() async {
        guard let api else { return }
        historyVersion += 1
        let version = historyVersion
        isRefreshing = true
        defer { if version == historyVersion { isRefreshing = false } }
        async let inputRefresh: Void = refreshRequiredInputs()
        do {
            let messages = try await api.fetchHistory()
            if !Task.isCancelled, version == historyVersion {
                applyHistory(messages)
                await syncDecisionActivity()
            }
        } catch {
            if !Task.isCancelled, version == historyVersion {
                loadError = error.localizedDescription
                didLoad = true
            }
        }
        await inputRefresh
    }

    /// Commit a fresh history snapshot and re-arm all derived state.
    private func applyHistory(_ messages: [HistoryMessage]) {
        history = messages
        loadError = nil
        didLoad = true
        adoptHistoryReplies()
        rescheduleExpiries()
    }

}
