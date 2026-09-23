// Keeps wall discovery connected and coalesces invalidations into metadata reconciliation.
// Exports PanelsModel wall reception; dependencies: the ticket-scoped relay connection.

import Foundation

extension PanelsModel {
    func startWallSubscription(config: ConnectionConfig) {
        guard wallConnection == nil || wallConfig != config else { return }
        invalidateQuestionnaireCoverage()
        isWallConnected = false
        if wallConfig != config {
            for connection in relayConnections.values { connection.stop() }
            relayConnections.removeAll()
            liveSubscriptions.removeAll()
        }
        wallConnection?.stop()
        wallConfig = config
        let connection = PanelRelayConnection(config: config, panelID: "wall", isWall: true) { [weak self] frame in
            guard self?.wallConfig == config else { return }
            self?.receiveWall(frame)
        } onDisconnect: { [weak self] in
            guard self?.wallConfig == config else { return }
            self?.wallConnectivityChanged(false)
        } onWallConnected: { [weak self] in
            guard self?.wallConfig == config else { return }
            self?.wallConnectivityChanged(true)
        }
        wallConnection = connection
        connection.start()
    }

    public func receiveWall(_ frame: PanelRelayFrame) {
        if frame == .subscriptionRevoked { wallConnectivityChanged(false); return }
        guard frame == .wallChanged, !isDemoMode else { return }
        reconcileSoon()
    }

    public func connectionDidChange() {
        invalidateQuestionnaireCoverage()
        wallConfig = nil
        wallConnection?.stop()
        wallConnection = nil
        isWallConnected = false
        relayConfig = nil
        for connection in relayConnections.values { connection.stop() }
        relayConnections.removeAll()
        liveSubscriptions.removeAll()
        reconcileSoon()
    }

    func wallConnectivityChanged(_ connected: Bool) {
        isWallConnected = connected
        reconcileSoon()
    }

    func reconcileSoon() {
        invalidateQuestionnaireCoverage()
        if isFetching || isLoadingQuestions { needsReconcile = true; return }
        guard reconciliationTask == nil else { return }
        reconciliationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled, let self else { return }
            self.reconciliationTask = nil
            await self.load()
        }
    }
}
