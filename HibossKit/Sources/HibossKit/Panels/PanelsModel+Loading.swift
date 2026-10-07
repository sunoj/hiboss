// Reconciles metadata without discarding live stores, selection, or form drafts.
// Exports PanelsModel loading and preference mutation behavior.
// Dependencies: PanelsServing, versioned checkpoints, and shared panel contracts.

import Foundation

extension PanelsModel {
    #if os(iOS)
    public func retryLoading() async {
        loadOperation += 1
        questionnaireOperation += 1
        isFetching = false
        isLoadingQuestions = false
        needsReconcile = false
        reconciliationTask?.cancel()
        reconciliationTask = nil
        await load()
    }
    #endif

    public func openWhenLoaded(_ tileID: String) async -> Bool {
        if !tiles.contains(where: { $0.id == tileID }) {
            #if os(iOS)
            let deadline = ContinuousClock.now + .seconds(15)
            #endif
            while isFetching {
                #if os(iOS)
                guard ContinuousClock.now < deadline else { return false }
                #endif
                do { try await Task.sleep(for: .milliseconds(50)) }
                catch { return false }
            }
            if !tiles.contains(where: { $0.id == tileID }) { await load() }
        }
        guard !Task.isCancelled, tiles.contains(where: { $0.id == tileID }) else { return false }
        open(tileID)
        return true
    }

    public func load() async {
        guard !isDemoMode else { return }
        invalidateQuestionnaireCoverage()
        guard !isFetching else { needsReconcile = true; return }
        isFetching = true
        #if os(iOS)
        loadOperation += 1
        let operation = loadOperation
        #endif
        var generation = questionnaireGeneration
        if tiles.isEmpty { loadState = .loading }
        defer {
            #if os(iOS)
            if operation == loadOperation { finishLoad() }
            #else
            finishLoad()
            #endif
        }
        do {
            let service = try await panelService()
            guard generation == questionnaireGeneration else { return }
            if let relayConfig { startWallSubscription(config: relayConfig) }
            generation = questionnaireGeneration
            let summaries = try await service.fetchPanels()
            let additions = try await fetchAdditions(summaries, service: service)
            guard generation == questionnaireGeneration else { return }
            var fetched: [PanelTile] = []
            for summary in summaries {
                recordServerClock(summary)
                fetched.append(
                    try reconcile(
                        summary, addition: additions[summary.panelId],
                        order: (tiles.map(\.order).max().map { $0 + 1 } ?? 0) + fetched.count))
            }
            let retained = Set(fetched.map(\.id))
            for id in relayConnections.keys where !retained.contains(id) {
                relayConnections.removeValue(forKey: id)?.stop()
                relayStates.removeValue(forKey: id)
                liveSubscriptions.remove(id)
            }
            tiles = fetched.sorted { $0.order < $1.order }
            if let selectedTileID, !retained.contains(selectedTileID) { self.selectedTileID = nil }
            loadState = .loaded
            if let relayConfig { startSubscriptions(config: relayConfig) }
            await refreshPendingQuestionnaires(using: service as? any QuestionnaireServing)
        } catch {
            guard generation == questionnaireGeneration else { return }
            loadState = .failed(error.localizedDescription)
        }
    }

    private func recordServerClock(_ summary: PanelMetadata) {
        serverClocks[summary.panelId] = (
            Date(timeIntervalSince1970: Double(summary.serverTime) / 1000),
            ProcessInfo.processInfo.systemUptime, Date()
        )
    }

    private func finishLoad() {
        isFetching = false
        lastReconciled = Date()
        if needsReconcile { needsReconcile = false; reconcileSoon() }
    }

    private func reconcile(_ summary: PanelMetadata, addition: PanelAddition?, order: Int) throws -> PanelTile
    {
        if var existing = tiles.first(where: {
            $0.id == summary.panelId && $0.definitionRevision == summary.definitionRevision
        }) {
            guard summary.metadataVersion >= (existing.metadata?.metadataVersion ?? 0) else {
                return existing
            }
            existing.metadata = summary
            if let final = summary.finalSnapshot {
                existing.store.replaceTask(final.task)
                relayConnections.removeValue(forKey: existing.id)?.stop()
                liveSubscriptions.remove(existing.id)
            }
            return existing
        }
        guard let addition else { throw HibossAPIError.invalidResponse }
        let (detail, checkpoint) = (addition.detail, addition.checkpoint)
        let fixture = PanelFixture(remote: detail)
        let store = PanelStore(fixture: fixture)
        guard checkpoint.definitionRevision == detail.definition.definitionRevision else {
            throw HibossAPIError.invalidResponse
        }
        store.replaceTask(checkpoint.task)
        relayConnections.removeValue(forKey: summary.panelId)?.stop()
        liveSubscriptions.remove(summary.panelId)
        var state = PanelRelayState(
            panelID: summary.panelId, definitionRevision: detail.definition.definitionRevision)
        _ = state.apply(.snapshot(checkpoint))
        relayStates[summary.panelId] = state
        return PanelTile(
            id: summary.panelId, fixture: fixture, store: store, producer: nil, agentID: summary.agentId,
            agentName: summary.agentName, sessionLabel: summary.sessionLabel,
            definitionRevision: detail.definition.definitionRevision,
            order: order, metadata: detail.metadata)
    }

    public func setPreference(
        _ tile: PanelTile, placement: PanelPlacement? = nil, seen: Int? = nil, acknowledge: Bool = false
    ) async {
        guard let current = tiles.first(where: { $0.id == tile.id }), let metadata = current.metadata else {
            return
        }
        #if os(iOS)
        guard !pendingPreferenceIDs.contains(tile.id) else { return }
        pendingPreferenceIDs.insert(tile.id)
        defer { pendingPreferenceIDs.remove(tile.id) }
        #endif
        do {
            let service = try await panelService()
            let preference = try await service.updatePanelPreference(tile.id, command: PanelPreferenceCommand(
                expectedPreferenceVersion: metadata.preference.preferenceVersion, placement: placement,
                    seenTerminalVersion: seen,
                    acknowledgedTerminalVersion: acknowledge ? metadata.metadataVersion : nil))
            if let index = tiles.firstIndex(where: { $0.id == tile.id }) {
                tiles[index].metadata?.preference = preference
            }
            preferenceError = nil
        } catch { preferenceError = error.localizedDescription; await load() }
    }
}
