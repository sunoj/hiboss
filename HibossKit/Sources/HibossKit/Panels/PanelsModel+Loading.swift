// Reconciles metadata without discarding live stores, selection, or form drafts.
// Exports PanelsModel loading and preference mutation behavior.
// Dependencies: PanelsServing, versioned checkpoints, and shared panel contracts.

import Foundation

extension PanelsModel {
    public func load() async {
        guard !isDemoMode, !isFetching else { return }
        isFetching = true
        if tiles.isEmpty { loadState = .loading }
        defer { isFetching = false; lastReconciled = Date() }
        do {
            let service = try await panelService()
            let summaries = try await service.fetchPanels()
            var fetched: [PanelTile] = []
            for summary in summaries {
                serverClocks[summary.panelId] = (Date(timeIntervalSince1970: Double(summary.serverTime) / 1000), ProcessInfo.processInfo.systemUptime, Date())
                fetched.append(try await reconcile(summary, service: service, order: (tiles.map(\.order).max().map { $0 + 1 } ?? 0) + fetched.count))
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
        } catch { loadState = .failed(error.localizedDescription) }
    }

    private func reconcile(_ summary: PanelMetadata, service: any PanelsServing, order: Int) async throws -> PanelTile {
        if var existing = tiles.first(where: { $0.id == summary.panelId && $0.definitionRevision == summary.definitionRevision }) {
            guard summary.metadataVersion >= (existing.metadata?.metadataVersion ?? 0) else { return existing }
            existing.metadata = summary
            if let final = summary.finalSnapshot {
                existing.store.replaceTask(final.task)
                relayConnections.removeValue(forKey: existing.id)?.stop()
                liveSubscriptions.remove(existing.id)
            }
            return existing
        }
        let detail = try await service.fetchPanel(summary.panelId)
        let fixture = PanelFixture(remote: detail)
        let store = PanelStore(fixture: fixture)
        let checkpoint = try await service.fetchPanelState(summary.panelId)
        guard checkpoint.definitionRevision == detail.definition.definitionRevision else { throw HibossAPIError.invalidResponse }
        store.replaceTask(checkpoint.task)
        relayConnections.removeValue(forKey: summary.panelId)?.stop()
        liveSubscriptions.remove(summary.panelId)
        var state = PanelRelayState(panelID: summary.panelId, definitionRevision: detail.definition.definitionRevision)
        _ = state.apply(.snapshot(checkpoint))
        relayStates[summary.panelId] = state
        return PanelTile(id: summary.panelId, fixture: fixture, store: store, producer: nil, agentID: summary.agentId,
            agentName: summary.agentName, sessionLabel: summary.sessionLabel, definitionRevision: detail.definition.definitionRevision,
            order: order, metadata: detail.metadata)
    }

    public func setPreference(_ tile: PanelTile, placement: PanelPlacement? = nil, seen: Int? = nil, acknowledge: Bool = false) async {
        guard let current = tiles.first(where: { $0.id == tile.id }), let metadata = current.metadata else { return }
        do {
            let service = try await panelService()
            let preference = try await service.updatePanelPreference(tile.id, command: PanelPreferenceCommand(
                expectedPreferenceVersion: metadata.preference.preferenceVersion, placement: placement,
                seenTerminalVersion: seen, acknowledgedTerminalVersion: acknowledge ? metadata.metadataVersion : nil))
            if let index = tiles.firstIndex(where: { $0.id == tile.id }) { tiles[index].metadata?.preference = preference }
            preferenceError = nil
        } catch { preferenceError = error.localizedDescription; await load() }
    }
}
