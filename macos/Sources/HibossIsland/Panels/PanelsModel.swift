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

    init(api: (any PanelsServing)? = nil, demoMode: Bool? = nil, autoload: Bool = true) {
        self.api = api
        isDemoMode = demoMode ?? (ProcessInfo.processInfo.environment["HIBOSS_PANELS_DEMO"] == "1")
        if isDemoMode, let fixtures = try? PanelFixtures.load() {
            self.fixtures = fixtures
            tiles = fixtures.all.enumerated().map { index, fixture in
                let producer = PanelDemoProducer.catalog[index]
                return PanelTile(id: fixture.name, fixture: fixture, store: PanelStore(fixture: fixture), producer: producer, agentID: nil, order: index)
            }
            lastUpdated = Dictionary(uniqueKeysWithValues: tiles.map { ($0.id, Date()) })
            loadState = .loaded
            startSimulation()
        } else {
            fixtures = nil
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
                    order: index
                ))
            }
            tiles = fetchedTiles
            selectedTileID = nil
            fetchedAt = Date()
            loadState = .loaded
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

    func freshness(for tile: PanelTile) -> PanelFreshness {
        if tile.agentID != nil {
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
        return HibossAPI(config: config)
    }

    private func startSimulation() {
        clockTask = Task { [weak self] in await self?.runClock() }
        producerTasks = tiles.indices.map { index in Task { [weak self] in await self?.runProducer(at: index) } }
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
    }
}

struct PanelTile: Identifiable {
    let id: String
    let fixture: PanelFixture
    let store: PanelStore
    let producer: PanelDemoProducer?
    let agentID: String?
    let order: Int

    var sourceLabel: String {
        if let producer { return producer.name }
        return "Agent ID: \(agentID ?? "not supplied")"
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
