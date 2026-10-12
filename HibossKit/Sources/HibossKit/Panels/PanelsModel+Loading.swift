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
        guard !isDemoMode, !isFetching else { return }
        reconciliationTask?.cancel()
        reconciliationTask = nil
        invalidateQuestionnaireCoverage(preservingCached: true)
        isFetching = true
        reportPanelCoverage()
        loadOperation += 1
        let operation = loadOperation
        var generation = questionnaireGeneration
        if tiles.isEmpty && !didLoadPanels { loadState = .loading }
        defer {
            if operation == loadOperation { finishLoad() }
        }
        do {
            let service = try await panelService()
            guard generation == questionnaireGeneration else { return }
            if let relayConfig { startWallSubscription(config: relayConfig) }
            generation = questionnaireGeneration
            let wallWasConnected = isWallConnected
            async let questions: Void = refreshPendingQuestionnaires(
                using: service as? any QuestionnaireServing, generation: generation)
            try await loadPanels(using: service, generation: generation)
            await questions
            try await revalidateAcknowledgedPanels(
                using: service, generation: generation, wallWasConnected: wallWasConnected)
        } catch {
            guard generation == questionnaireGeneration else { return }
            loadState = .failed(error.localizedDescription)
        }
    }

    private func loadPanels(using service: any PanelsServing, generation: UInt64) async throws {
        do {
            let summaries = try await service.fetchPanels()
            try await installPanels(summaries, using: service, generation: generation)
        } catch {
            if generation == questionnaireGeneration { loadState = .failed(error.localizedDescription) }
            throw error
        }
    }

    private func revalidateAcknowledgedPanels(
        using service: any PanelsServing, generation: UInt64, wallWasConnected: Bool
    ) async throws {
        // The acknowledgement can arrive after panels finish while questionnaires remain in flight.
        // Recheck across the whole joined load; wall acknowledgement has no replay cursor.
        if wallConnection != nil, !wallWasConnected, isWallConnected,
           generation == questionnaireGeneration {
            let current = try await service.fetchPanels()
            try await installPanels(current, using: service, generation: generation)
        }
    }

    private func installPanels(
        _ summaries: [PanelMetadata], using service: any PanelsServing, generation: UInt64
    ) async throws {
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
        didLoadPanels = true
        StartupLog.record("panels loaded", count: tiles.count)
        if let relayConfig { startSubscriptions(config: relayConfig) }
    }

    private func recordServerClock(_ summary: PanelMetadata) {
        serverClocks[summary.panelId] = (
            Date(timeIntervalSince1970: Double(summary.serverTime) / 1000),
            ProcessInfo.processInfo.systemUptime, Date()
        )
    }

    private func finishLoad() {
        isFetching = false
        retainedRefreshCoverage = false
        reportPanelCoverage()
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
        let identity = identityGeneration
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
            guard identity == identityGeneration else { return }
            if let index = tiles.firstIndex(where: { $0.id == tile.id }) {
                tiles[index].metadata?.preference = preference
            }
            preferenceError = nil
        } catch {
            guard identity == identityGeneration else { return }
            preferenceError = error.localizedDescription
            await load()
        }
    }
}
