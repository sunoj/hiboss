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
        if authorizationRejected && !AccountAuthorization.shared.hasRejectedAccount {
            authorizationRejected = false
        }
        identityGeneration &+= 1
        loadOperation += 1
        questionnaireOperation += 1
        reconciliationTask?.cancel()
        reconciliationTask = nil
        needsReconcile = false
        isFetching = false
        isLoadingQuestions = false
        activeQuestionnaireGeneration = nil
        producerTasks.forEach { $0.cancel() }
        producerTasks.removeAll()
        selectedTileID = nil
        tiles = []
        pendingQuestionnaires = []
        didLoadPanels = false
        loadState = .loading
        questionnaireError = nil
        preferenceError = nil
        pendingPreferenceIDs = []
        relayStates = [:]
        serverClocks = [:]
        lastUpdated = [:]
        didLoadQuestionnaires = false
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
        guard !connected || isWallConnected != connected else { return }
        isWallConnected = connected
        if connected, isFetching || isLoadingQuestions {
            if !isLoadingQuestions {
                let generation = questionnaireGeneration
                Task { [weak self] in await self?.recheckAcknowledgedQuestionnaires(generation) }
            }
            return
        }
        reconcileSoon()
    }

    private func recheckAcknowledgedQuestionnaires(_ generation: UInt64) async {
        do {
            let service = try await panelService()
            guard generation == questionnaireGeneration else { return }
            await refreshPendingQuestionnaires(
                using: service as? any QuestionnaireServing, generation: generation)
        } catch {
            guard generation == questionnaireGeneration else { return }
            questionnaireError = error.localizedDescription
        }
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
