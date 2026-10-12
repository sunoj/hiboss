// Synchronizes option-flow history and session inventory for native clients.
// Exports OptionFlowStore history operations and typed authorization handling.
// Dependencies: HistorySync, BossServing and SessionsServing.

import Foundation

extension OptionFlowStore {
    public func refreshHistory() async {
        guard let historySync else { return }
        let version = historyVersion
        isRefreshingHistory = true
        defer { if version == historyVersion { isRefreshingHistory = false } }
        if case .failed = historyState {} else { historyState = .loading }
        await historySync.synchronize(forceFull: true)
    }

    private func refreshProjectSessions() async {
        let version = historyVersion
        guard let sessionsAPI = api as? any SessionsServing else { return }
        let sessions = (try? await sessionsAPI.projectSessions()) ?? []
        if version == historyVersion, projectSessions != sessions { projectSessions = sessions }
    }

    func configureHistorySync(_ api: any BossServing) {
        let version = historyVersion
        historySync = HistorySync(api: api) { [weak self] messages, error in
            guard let self, version == self.historyVersion else { return }
            if case let .authorization(rejection) = error {
                AccountAuthorization.shared.reject(rejection)
                return
            }
            if let messages {
                self.historyMessages = messages
                self.reconcileActiveAgainstHistory()
            }
            let state: HistoryState = error.map { .failed($0.localizedDescription) } ?? .loaded
            if error == nil { self.historyLoadedAt = .now }
            if self.historyState != state { self.historyState = state }
            if error == nil { await self.refreshProjectSessions() }
        }
    }

    func refreshHistoryInBackground(debounced: Bool = true) {
        guard let historySync else { return }
        historyTask = Task { await historySync.synchronize(debounced: debounced) }
    }
}
