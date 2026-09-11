// Keeps wall discovery connected and coalesces invalidations into metadata reconciliation.
// Exports PanelsModel wall reception; dependencies: the ticket-scoped relay connection.

import Foundation

extension PanelsModel {
    func startWallSubscription(config: ConnectionConfig) {
        guard wallConnection == nil || wallConfig != config else { return }
        wallConnection?.stop()
        wallConfig = config
        let connection = PanelRelayConnection(config: config, panelID: "wall", isWall: true) { [weak self] frame in
            self?.receiveWall(frame)
        } onDisconnect: {}
        wallConnection = connection
        connection.start()
    }

    public func receiveWall(_ frame: PanelRelayFrame) {
        guard frame == .wallChanged, !isDemoMode else { return }
        reconcileSoon()
    }

    func reconcileSoon() {
        if isFetching { needsReconcile = true; return }
        guard reconciliationTask == nil else { return }
        reconciliationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled, let self else { return }
            self.reconciliationTask = nil
            await self.load()
        }
    }
}
