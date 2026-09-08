// Loads server-backed panels and preserves the fixture wall for explicit demo mode.
// Exports: PanelsModel, PanelTile, and PanelFreshness.
// Dependencies: PanelsServing, injected ConnectionConfig, and panel renderer models.

import SwiftUI

public enum PanelsLoadState: Equatable {
    case idle, loading, loaded, failed(String)
}

public enum PanelClientError: LocalizedError {
    case notConfigured

    public var errorDescription: String? {
        switch self { case .notConfigured: "Connect HiBoss to load panels." }
    }
}

@MainActor
public final class PanelsModel: ObservableObject {
    public let fixtures: PanelFixtureSet?
    public let isDemoMode: Bool
    public let webModel = PanelWebModel()
    @Published public internal(set) var tiles: [PanelTile] = []
    @Published public internal(set) var selectedTileID: String?
    @Published public internal(set) var now = Date()
    @Published public internal(set) var loadState: PanelsLoadState = .idle
    let api: (any PanelsServing)?
    let configurationProvider: (@MainActor () async throws -> ConnectionConfig)?
    var lastUpdated: [String: Date] = [:]
    var isFetching = false
    var lastReconciled = Date.distantPast
    @Published public var section: PanelWallSection = .active
    @Published public internal(set) var preferenceError: String?
    var producerTasks: [Task<Void, Never>] = []
    var clockTask: Task<Void, Never>?
    var serverClocks: [String: (server: Date, uptime: TimeInterval, wall: Date)] = [:]
    var relayStates: [String: PanelRelayState] = [:]
    var relayConnections: [String: PanelRelayConnection] = [:]
    var liveSubscriptions: Set<String> = []
    var relayConfig: ConnectionConfig?

    public init(
        api: (any PanelsServing)? = nil,
        configurationProvider: (@MainActor () async throws -> ConnectionConfig)? = nil,
        demoMode: Bool? = nil,
        autoload: Bool = true
    ) {
        self.api = api
        self.configurationProvider = configurationProvider
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

    public var selectedTile: PanelTile? { tiles.first { $0.id == selectedTileID } }
    public var isLoading: Bool { if case .loading = loadState { true } else { false } }
    public var failureMessage: String? { if case let .failed(message) = loadState { message } else { nil } }

    public func loadIfNeeded() async {
        guard !isDemoMode, loadState == .idle else { return }
        await load()
    }

    public func positions(for width: CGFloat) -> [PanelTilePosition] {
        PanelWallLayout.arrange(visibleTiles.map { PanelLayoutPanel(id: $0.id, size: $0.fixture.spec.tileSize, order: $0.order, isPinned: $0.preference.placement == .pinned) }, width: width)
    }

    public nonisolated func wallHeight(of positions: [PanelTilePosition]) -> CGFloat {
        (positions.map { $0.frame.maxY }.max() ?? 0) + 8
    }

    public func open(_ tileID: String) {
        selectedTileID = tileID
        guard let tile = tiles.first(where: { $0.id == tileID }), let metadata = tile.metadata,
              tile.lifecycle.taskState.isTerminal, tile.preference.seenTerminalVersion != metadata.metadataVersion else { return }
        Task { await setPreference(tile, seen: metadata.metadataVersion) }
    }
    public func closeDetail() { selectedTileID = nil }

    public func animationDelay(for tile: PanelTile) -> Double { Double(tile.order) * 0.045 }

    func panelService() async throws -> any PanelsServing {
        if let api { return api }
        guard let configurationProvider else { throw PanelClientError.notConfigured }
        let config = try await configurationProvider()
        relayConfig = config
        return HibossAPI(config: config)
    }

    func startSimulation() {
        startClock()
        producerTasks = tiles.indices.map { index in Task { [weak self] in await self?.runProducer(at: index) } }
    }

    func startClock() {
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: PanelDemoProducer.clockIntervalNanoseconds)
                guard !Task.isCancelled else { return }
                self?.now = Date()
                guard let self, !self.isDemoMode, !self.isFetching, Date().timeIntervalSince(self.lastReconciled) > 10 else { continue }
                await self.load()
            }
        }
    }

    func runProducer(at index: Int) async {
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
