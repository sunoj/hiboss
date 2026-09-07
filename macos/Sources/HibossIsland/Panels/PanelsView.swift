// Live Tile-style Panels wall with drill-in rendering for the full panel surface.
// Exports: PanelsView, PanelsModel, PanelTile, and PanelFreshness.
// Dependencies: SwiftUI, PanelFixtures, PanelStore, PanelRenderer, and PanelWallLayout.

import SwiftUI

struct PanelsView: View {
    @StateObject private var model = PanelsModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Panels").font(.largeTitle.bold())
                    Text("Seven producers, one living wall.").font(.callout).foregroundStyle(.secondary)
                }
                sampleNotice
                if let tile = model.selectedTile {
                    PanelDetail(tile: tile, model: model)
                } else if !model.tiles.isEmpty {
                    PanelWall(model: model, reduceMotion: reduceMotion)
                } else {
                    ContentUnavailableView("Fixtures unavailable", systemImage: "doc.questionmark")
                }
            }
            .padding(24)
            // A single panel is a reading surface and keeps a column width. The wall is
            // not: capping it at 720 leaves room for exactly one wide tile, so it could
            // never actually become a wall however large the window got.
            .frame(maxWidth: model.selectedTile == nil ? .infinity : 720, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sampleNotice: some View {
        Label("Sample data — fixture preview only; no live agent panel is connected.", systemImage: "info.circle")
            .font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

}

private struct PanelWall: View {
    @ObservedObject var model: PanelsModel
    let reduceMotion: Bool
    @State private var measuredWidth: CGFloat = 640

    var body: some View {
        GeometryReader { proxy in
            let positions = model.positions(for: proxy.size.width)
            ZStack(alignment: .topLeading) {
                ForEach(model.tiles) { tile in
                    if let position = positions.first(where: { $0.id == tile.id }) {
                        PanelTileCard(tile: tile, model: model, reduceMotion: reduceMotion)
                            .frame(width: position.frame.width, height: position.frame.height)
                            .offset(x: position.frame.minX, y: position.frame.minY)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear { measuredWidth = proxy.size.width }
            .onChange(of: proxy.size.width) { measuredWidth = $0 }
        }
        .frame(height: model.wallHeight(of: model.positions(for: measuredWidth)))
    }
}

private struct PanelTileCard: View {
    let tile: PanelTile
    @ObservedObject var model: PanelsModel
    let reduceMotion: Bool
    @State private var pulse = false

    var body: some View {
        Button { model.open(tile.id) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Text(tile.fixture.title).font(.headline).lineLimit(2)
                    Spacer(minLength: 4)
                    freshnessBadge
                }
                Text(tile.producer.name).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                summary
                Spacer(minLength: 0)
                Label("Open panel", systemImage: "arrow.up.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary))
            .scaleEffect(pulse ? 1.015 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tile.fixture.title), producer \(tile.producer.name), \(model.freshness(for: tile).title)")
        .onChange(of: tile.store.state) { _, _ in
            guard !reduceMotion else { return }
            pulse = true
            withAnimation(.easeOut(duration: 0.28).delay(model.animationDelay(for: tile))) {
                pulse = false
            }
        }
    }

    private var freshnessBadge: some View {
        let freshness = model.freshness(for: tile)
        return Label(freshness.title, systemImage: freshness.symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(freshness.color)
            .fixedSize()
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(summaryLines.prefix(3).enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline) {
                    Text(line.label).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(line.value).font(.caption.monospacedDigit()).lineLimit(1)
                }
            }
        }
    }

    private var summaryLines: [PanelSummaryLine] {
        tile.fixture.spec.elements.values
            .filter { ["Metric", "Progress", "Status"].contains($0.type) }
            .sorted { $0.props["label"]?.string ?? "" < $1.props["label"]?.string ?? "" }
            .map { element in
                let label = element.props["label"]?.string ?? element.type
                let value = element.type == "Status"
                    ? element.props["message"]?.string ?? element.props["status"]?.string ?? "—"
                    : summaryValue(element.props["value"])
                return PanelSummaryLine(label: label, value: value)
            }
    }

    private func summaryValue(_ value: PanelJSONValue?) -> String {
        guard let value else { return "—" }
        if let path = value.object?["$state"]?.string {
            return panelValue(at: path, in: tile.store.state)?.displayText ?? "—"
        }
        return value.displayText.isEmpty ? "—" : value.displayText
    }
}

private struct PanelSummaryLine {
    let label: String
    let value: String
}

private struct PanelDetail: View {
    let tile: PanelTile
    @ObservedObject var model: PanelsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("Back to wall", systemImage: "arrow.left") { model.closeDetail() }
                Spacer()
                Label(model.freshness(for: tile).title, systemImage: model.freshness(for: tile).symbol)
                    .foregroundStyle(model.freshness(for: tile).color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(tile.fixture.title).font(.title.bold())
                Text("Produced by \(tile.producer.name)").font(.callout).foregroundStyle(.secondary)
            }
            PanelRenderer(spec: tile.fixture.spec, store: tile.store, webModel: model.webModel)
                .render(tile.fixture.spec.root)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let answer = tile.store.submittedAnswerText {
                Text("Captured submission").font(.headline).padding(.top, 10)
                if tile.store.submissionWasEdited {
                    Text("Form edited since submission; this is the previous answer, not the current draft.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Text(answer).font(.body.monospaced()).textSelection(.enabled).foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
final class PanelsModel: ObservableObject {
    let fixtures: PanelFixtureSet?
    let tiles: [PanelTile]
    let webModel = PanelWebModel()
    @Published private(set) var selectedTileID: String?
    @Published private(set) var now = Date()
    private var lastUpdated: [String: Date] = [:]
    private var producerTasks: [Task<Void, Never>] = []
    private var clockTask: Task<Void, Never>?

    init() {
        guard let fixtures = try? PanelFixtures.load() else {
            self.fixtures = nil
            tiles = []
            return
        }
        self.fixtures = fixtures
        let fixtureList = fixtures.all
        tiles = fixtureList.enumerated().map { index, fixture in
            let producer = PanelDemoProducer.catalog[index]
            return PanelTile(id: fixture.name, fixture: fixture, store: PanelStore(fixture: fixture), producer: producer, order: index)
        }
        lastUpdated = Dictionary(uniqueKeysWithValues: tiles.map { ($0.id, Date()) })
        startSimulation()
    }

    var selectedTile: PanelTile? { tiles.first { $0.id == selectedTileID } }

    func positions(for width: CGFloat) -> [PanelTilePosition] {
        PanelWallLayout.arrange(tiles.map { PanelLayoutPanel(id: $0.id, size: $0.fixture.spec.tileSize, order: $0.order, isPinned: false) }, width: width)
    }

    // Takes the placed positions rather than a width, so the container height cannot
    // be computed from a different width than the tiles were laid out with.
    nonisolated func wallHeight(of positions: [PanelTilePosition]) -> CGFloat {
        (positions.map { $0.frame.maxY }.max() ?? 0) + 8
    }

    func open(_ tileID: String) { selectedTileID = tileID }

    func closeDetail() { selectedTileID = nil }

    func freshness(for tile: PanelTile) -> PanelFreshness {
        guard let updated = lastUpdated[tile.id] else { return .offline }
        let age = now.timeIntervalSince(updated)
        if age < 5 { return .live }
        if age < 15 { return .stale }
        return .offline
    }

    func animationDelay(for tile: PanelTile) -> Double {
        Double(tile.order) * 0.045
    }

    private func startSimulation() {
        clockTask = Task { [weak self] in await self?.runClock() }
        producerTasks = tiles.indices.map { index in
            Task { [weak self] in await self?.runProducer(at: index) }
        }
    }

    private func runClock() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: PanelDemoProducer.clockIntervalNanoseconds)
            guard !Task.isCancelled else { return }
            now = Date()
        }
    }

    private func runProducer(at index: Int) async {
        let producer = tiles[index].producer
        if producer.startDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: producer.startDelayNanoseconds)
        }
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
    let producer: PanelDemoProducer
    let order: Int
}

enum PanelFreshness {
    case live, stale, offline

    var title: String {
        switch self { case .live: "Live"; case .stale: "Stale"; case .offline: "Offline" }
    }

    var symbol: String {
        switch self { case .live: "dot.radiowaves.left.and.right"; case .stale: "clock.badge.exclamationmark"; case .offline: "wifi.slash" }
    }

    var color: Color {
        switch self { case .live: .green; case .stale: .orange; case .offline: .secondary }
    }
}
