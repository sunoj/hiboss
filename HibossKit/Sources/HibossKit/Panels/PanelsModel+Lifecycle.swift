// Projects lifecycle, freshness, and placement into native panel walls.
// Exports filtered tiles and relay reconciliation for PanelsModel.
// Dependencies: server checkpoint deadlines, PanelRelayConnection, and tile metadata.

import Foundation

extension PanelsModel {
    public var visibleTiles: [PanelTile] {
        tiles.filter { tile in
            switch section {
            case .needsInput: return pendingCount(for: tile) > 0
            case .archived: return tile.preference.placement == .archived
            case .results: return tile.lifecycle.taskState.isTerminal
            case .active:
                guard panelIsVisibleInActiveWall(taskState: tile.lifecycle.taskState,
                    placement: tile.preference.placement, expiresAt: expiry(for: tile), serverTime: serverNow(for: tile.id)) else { return false }
                if tile.preference.placement == .pinned || !tile.lifecycle.taskState.isTerminal { return true }
                if tile.preference.acknowledgedTerminalVersion == tile.metadata?.metadataVersion { return false }
                return panelDate(tile.lifecycle.dismissAt).map { $0 > serverNow(for: tile.id) } ?? true
            }
        }
    }
    public var unreadResults: Int {
        tiles.filter { $0.lifecycle.taskState.isTerminal && $0.preference.seenTerminalVersion != $0.metadata?.metadataVersion }.count
    }

    public func serverNow(for id: String) -> Date {
        serverClocks[id].map { $0.server.addingTimeInterval(ProcessInfo.processInfo.systemUptime - $0.uptime) } ?? now
    }

    private func expiry(for tile: PanelTile) -> Date? {
        [panelDate(tile.lifecycle.expiresAt), panelDate(relayStates[tile.id]?.checkpoint?.expiresAt)].compactMap { $0 }.max()
    }

    public func freshness(for tile: PanelTile, at reference: Date? = nil) -> PanelFreshness {
        let anchor = serverClocks[tile.id]
        let now = anchor.map { anchor in
            anchor.server.addingTimeInterval(reference.map { $0.timeIntervalSince(anchor.wall) } ?? (ProcessInfo.processInfo.systemUptime - anchor.uptime))
        } ?? reference ?? self.now
        if tile.lifecycle.taskState != .running { return .task(tile.lifecycle.taskState) }
        if tile.agentID != nil {
            guard let checkpoint = relayStates[tile.id]?.checkpoint else { return .awaitingData }
            guard checkpoint.lastObservedAt != nil else { return .awaitingData }
            guard liveSubscriptions.contains(tile.id) else { return .offline }
            guard let lease = panelDate(checkpoint.leaseExpiresAt), lease > now else { return .offline }
            guard let stale = panelDate(checkpoint.staleAt), stale > now else { return .stale }
            return .live
        }
        guard let updated = lastUpdated[tile.id] else { return .offline }
        let age = now.timeIntervalSince(updated)
        return age < 5 ? .live : age < 15 ? .stale : .offline
    }

    func startSubscriptions(config: ConnectionConfig) {
        for tile in tiles where tile.agentID != nil && !tile.lifecycle.taskState.isTerminal && relayConnections[tile.id] == nil {
            let connection = PanelRelayConnection(config: config, panelID: tile.id) { [weak self] frame in
                self?.receive(frame, for: tile.id)
            } onDisconnect: { [weak self] in self?.liveSubscriptions.remove(tile.id) }
            relayConnections[tile.id] = connection
            connection.start()
        }
    }

    public func receive(_ frame: PanelRelayFrame, for tileID: String) {
        if frame == .metadataChanged { reconcileSoon(); return }
        if frame == .subscriptionRevoked {
            liveSubscriptions.remove(tileID)
            relayConnections.removeValue(forKey: tileID)?.stop()
            Task { await load() }
            return
        }
        guard let tile = tiles.first(where: { $0.id == tileID }), let revision = tile.definitionRevision,
              !tile.lifecycle.taskState.isTerminal else { return }
        var state = relayStates[tileID] ?? PanelRelayState(panelID: tileID, definitionRevision: revision)
        let result = state.apply(frame)
        if result == .resyncRequired { relayConnections[tileID]?.requestSnapshot(); return }
        guard result == .installed || result == .applied else { return }
        if let checkpoint = state.checkpoint {
            serverClocks[tileID] = (Date(timeIntervalSince1970: Double(checkpoint.serverTime) / 1000), ProcessInfo.processInfo.systemUptime, Date())
        }
        relayStates[tileID] = state
        liveSubscriptions.insert(tileID)
        tile.store.replaceTask(state.task)
    }
}
