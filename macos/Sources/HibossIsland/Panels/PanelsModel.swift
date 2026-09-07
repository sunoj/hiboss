// Loads server-backed panels and preserves the fixture wall for explicit demo mode.
// Exports: PanelsModel, PanelTile, and PanelFreshness.
// Dependencies: HibossKit PanelsServing, AppSettings, and panel renderer models.

import HibossKit
import SwiftUI

enum PanelsLoadState: Equatable {
    case idle, loading, loaded, failed(String)
}

enum PanelClientError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        switch self { case .notConfigured: "Connect this Mac to HiBoss to load panels." }
    }
}

@MainActor
final class PanelsModel: ObservableObject {
    let fixtures: PanelFixtureSet?
    let isDemoMode: Bool
    let webModel = PanelWebModel()
    @Published private(set) var tiles: [PanelTile] = []
    @Published private(set) var selectedTileID: String?
    @Published private(set) var now = Date()
    @Published private(set) var loadState: PanelsLoadState = .idle
    private let api: (any PanelsServing)?
    private var lastUpdated: [String: Date] = [:]
    private var fetchedAt: Date?
    private var producerTasks: [Task<Void, Never>] = []
    private var clockTask: Task<Void, Never>?
    private var relayStates: [String: PanelRelayState] = [:]
    private var relayConnections: [String: PanelRelayConnection] = [:]
    private var liveSubscriptions: Set<String> = []
    private var lastRelayActivity: [String: Date] = [:]
    private var relayConfig: ConnectionConfig?

    init(api: (any PanelsServing)? = nil, demoMode: Bool? = nil, autoload: Bool = true) {
        self.api = api
        isDemoMode = demoMode ?? (ProcessInfo.processInfo.environment["HIBOSS_PANELS_DEMO"] == "1")
        if isDemoMode, let fixtures = try? PanelFixtures.load() {
            self.fixtures = fixtures
            tiles = fixtures.all.enumerated().map { index, fixture in
                let producer = PanelDemoProducer.catalog[index]
                return PanelTile(id: fixture.name, fixture: fixture, store: PanelStore(fixture: fixture), producer: producer, agentID: nil, agentName: nil, sessionLabel: nil, definitionRevision: nil, order: index)
            }
            lastUpdated = Dictionary(uniqueKeysWithValues: tiles.map { ($0.id, Date()) })
            loadState = .loaded
            startSimulation()
        } else {
            fixtures = nil
            startClock()
            if autoload { Task { await load() } }
        }
    }

    var selectedTile: PanelTile? { tiles.first { $0.id == selectedTileID } }
    var isLoading: Bool { if case .loading = loadState { true } else { false } }
    var failureMessage: String? { if case let .failed(message) = loadState { message } else { nil } }

    func loadIfNeeded() async {
        guard !isDemoMode, loadState == .idle else { return }
        await load()
    }

    func load() async {
        guard !isDemoMode, loadState != .loading else { return }
        loadState = .loading
        do {
            let service = try await panelService()
            let metadata = try await service.fetchPanels()
            var fetchedTiles: [PanelTile] = []
            for (index, summary) in metadata.enumerated() {
                let detail = try await service.fetchPanel(summary.panelId)
                let fixture = PanelFixture(remote: detail)
                fetchedTiles.append(PanelTile(
                    id: detail.metadata.panelId,
                    fixture: fixture,
                    store: PanelStore(fixture: fixture),
                    producer: nil,
                    agentID: detail.metadata.agentId,
                    agentName: detail.metadata.agentName,
                    sessionLabel: detail.metadata.sessionLabel,
                    definitionRevision: detail.definition.definitionRevision,
                    order: index
                ))
            }
            relayConnections.values.forEach { $0.stop() }
            relayConnections.removeAll()
            relayStates.removeAll()
            liveSubscriptions.removeAll()
            lastRelayActivity.removeAll()
            tiles = fetchedTiles
            selectedTileID = nil
            fetchedAt = Date()
            loadState = .loaded
            if let relayConfig { startSubscriptions(config: relayConfig) }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func positions(for width: CGFloat) -> [PanelTilePosition] {
        PanelWallLayout.arrange(tiles.map { PanelLayoutPanel(id: $0.id, size: $0.fixture.spec.tileSize, order: $0.order, isPinned: false) }, width: width)
    }

    nonisolated func wallHeight(of positions: [PanelTilePosition]) -> CGFloat {
        (positions.map { $0.frame.maxY }.max() ?? 0) + 8
    }

    func open(_ tileID: String) { selectedTileID = tileID }
    func closeDetail() { selectedTileID = nil }

    /// Takes the reference time so a stalled subscription can be tested. A socket that
    /// quietly stops delivering is far commoner than one that is revoked, and it is the
    /// case where a green badge actively misleads: the tile says live, the agent died.
    func freshness(for tile: PanelTile, at reference: Date? = nil) -> PanelFreshness {
        let now = reference ?? self.now
        if tile.agentID != nil {
            if liveSubscriptions.contains(tile.id), let updated = lastRelayActivity[tile.id] {
                let age = now.timeIntervalSince(updated)
                if age < PanelRelayConnection.expectedInterval { return .live }
                if age < PanelRelayConnection.expectedInterval * 3 { return .stale }
                return .offline
            }
            return failureMessage == nil ? .fetched(fetchedAt ?? now) : .cachedFailure
        }
        guard let updated = lastUpdated[tile.id] else { return .offline }
        let age = now.timeIntervalSince(updated)
        if age < 5 { return .live }
        if age < 15 { return .stale }
        return .offline
    }

    func animationDelay(for tile: PanelTile) -> Double { Double(tile.order) * 0.045 }

    private func panelService() async throws -> any PanelsServing {
        if let api { return api }
        let settings = AppSettings()
        await settings.loadToken()
        guard case let .success(config) = settings.connectionConfig() else { throw PanelClientError.notConfigured }
        relayConfig = config
        return HibossAPI(config: config)
    }

    private func startSubscriptions(config: ConnectionConfig) {
        for tile in tiles where tile.agentID != nil {
            guard let revision = tile.definitionRevision else { continue }
            relayStates[tile.id] = PanelRelayState(panelID: tile.id, definitionRevision: revision)
            let connection = PanelRelayConnection(config: config, panelID: tile.id) { [weak self] frame in
                self?.receive(frame, for: tile.id)
            } onDisconnect: { [weak self] in
                self?.subscriptionLost(for: tile.id)
            }
            relayConnections[tile.id] = connection
            connection.start()
        }
    }

    func receive(_ frame: PanelRelayFrame, for tileID: String) {
        let connection = relayConnections[tileID]
        if case .subscriptionRevoked = frame {
            liveSubscriptions.remove(tileID)
            lastRelayActivity.removeValue(forKey: tileID)
            connection?.stop()
            return
        }
        guard let tile = tiles.first(where: { $0.id == tileID }), let revision = tile.definitionRevision else { return }
        var state = relayStates[tileID] ?? PanelRelayState(panelID: tileID, definitionRevision: revision)
        let result = state.apply(frame)
        relayStates[tileID] = state
        guard case .ignored = frame else {
            guard result != .rejected else { return }
            liveSubscriptions.insert(tileID)
            lastRelayActivity[tileID] = Date()
            if result == .resyncRequired { connection?.requestSnapshot() }
            if result == .installed || result == .applied, let index = tiles.firstIndex(where: { $0.id == tileID }) {
                tiles[index].store.replaceTask(PanelJSONValue(remote: state.task))
            }
            return
        }
    }

    private func subscriptionLost(for tileID: String) {
        liveSubscriptions.remove(tileID)
        lastRelayActivity.removeValue(forKey: tileID)
    }

    private func startSimulation() {
        startClock()
        producerTasks = tiles.indices.map { index in Task { [weak self] in await self?.runProducer(at: index) } }
    }

    private func startClock() {
        clockTask = Task { [weak self] in await self?.runClock() }
    }

    private func runClock() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: PanelDemoProducer.clockIntervalNanoseconds)
            guard !Task.isCancelled else { return }
            now = Date()
        }
    }

    private func runProducer(at index: Int) async {
        guard let producer = tiles[index].producer else { return }
        if producer.startDelayNanoseconds > 0 { try? await Task.sleep(nanoseconds: producer.startDelayNanoseconds) }
        var pushes = 0
        while !Task.isCancelled, producer.pushLimit.map({ pushes < $0 }) ?? true {
            try? await Task.sleep(nanoseconds: producer.intervalNanoseconds)
            guard !Task.isCancelled else { return }
            tiles[index].store.advanceDemoData(seed: pushes)
            lastUpdated[tiles[index].id] = Date()
            pushes += 1
        }
    }

    deinit {
        clockTask?.cancel()
        producerTasks.forEach { $0.cancel() }
        let connections = Array(relayConnections.values)
        Task { @MainActor in connections.forEach { $0.stop() } }
    }
}

struct PanelTile: Identifiable {
    let id: String
    let fixture: PanelFixture
    let store: PanelStore
    let producer: PanelDemoProducer?
    let agentID: String?
    let agentName: String?
    let sessionLabel: String?
    let definitionRevision: Int?
    let order: Int

    /// A server one version behind sends no name. Falling back to "Unknown agent" would
    /// be untrue — the agent is known, only its name is missing — so show a short form of
    /// the id, which is real, and let the project half fall away rather than inventing one.
    var sourceLabel: String {
        if let producer { return producer.name }
        let who = agentName ?? agentID.map { "agent \($0.prefix(8))" } ?? "Unattributed"
        guard let sessionLabel, !sessionLabel.isEmpty else { return who }
        return "\(who) · \(sessionLabel)"
    }
}

enum PanelFreshness {
    case live, stale, offline, fetched(Date), cachedFailure

    var title: String {
        switch self {
        case .live: "Live"
        case .stale: "Stale"
        case .offline: "Offline"
        case let .fetched(date): "Fetched \(date.formatted(date: .omitted, time: .shortened))"
        case .cachedFailure: "Cached — fetch failed"
        }
    }

    var symbol: String {
        switch self {
        case .live: "dot.radiowaves.left.and.right"
        case .stale: "clock.badge.exclamationmark"
        case .offline: "wifi.slash"
        case .fetched: "clock"
        case .cachedFailure: "exclamationmark.triangle"
        }
    }

    var color: Color {
        switch self {
        case .live: .green
        case .stale, .cachedFailure: .orange
        case .offline, .fetched: .secondary
        }
    }
}
