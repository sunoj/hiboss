// Embeddable Panels section and detail for the unified macOS dashboard.
// Exports: DashboardPanelsSection, PanelWall, and DashboardPanelDetail.
// Dependencies: SwiftUI and HibossKit panel models, rendering, and lifecycle controls.

import SwiftUI
import HibossKit

struct DashboardPanelsSection: View {
    @ObservedObject var model: PanelsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Panels").font(.title2.bold())
                Text("\(model.visibleTiles.count)").foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
            }
            PanelWallFilter(model: model)
            if model.isDemoMode {
                Label("Sample data · Local preview", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let failure = model.failureMessage {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry panels") { Task { await model.load() } }
            }
            if !model.visibleTiles.isEmpty {
                PanelWall(model: model)
            } else if !model.isLoading {
                ContentUnavailableView(
                    model.failureMessage == nil ? "No panels here" : "Panels unavailable",
                    systemImage: "rectangle.stack",
                    description: Text(model.failureMessage == nil
                        ? "Task progress and results appear here." : "Try again when the server is reachable.")
                )
                .frame(minHeight: 180)
            }
        }
        .accessibilityIdentifier("dashboard.panels")
    }
}

struct PanelWall: View {
    @ObservedObject var model: PanelsModel
    @State private var measuredWidth: CGFloat = 640

    var body: some View {
        GeometryReader { proxy in
            let positions = model.positions(for: proxy.size.width)
            ZStack(alignment: .topLeading) {
                ForEach(model.visibleTiles) { tile in
                    if let position = positions.first(where: { $0.id == tile.id }) {
                        PanelDashboardCard(tile: tile, freshness: model.freshness(for: tile)) { model.open(tile.id) }
                            .contextMenu { PanelLifecycleMenu(tile: tile, model: model) }
                            .frame(width: position.frame.width, height: position.frame.height)
                            .offset(x: position.frame.minX, y: position.frame.minY)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear { measuredWidth = proxy.size.width }
            .onChange(of: proxy.size.width) { _, width in measuredWidth = width }
        }
        .frame(height: model.wallHeight(of: model.positions(for: measuredWidth)))
    }
}

struct DashboardPanelDetail: View {
    let tile: PanelTile
    @ObservedObject var model: PanelsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("Close panel", systemImage: "xmark") { model.closeDetail() }
                Spacer()
                Label(model.freshness(for: tile).title, systemImage: model.freshness(for: tile).symbol)
                    .foregroundStyle(model.freshness(for: tile).color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(tile.fixture.title).font(.title.bold())
                Text(tile.sourceLabel).font(.callout).foregroundStyle(.secondary)
            }
            PanelOutcomeView(tile: tile)
            Menu("Panel actions") { PanelLifecycleMenu(tile: tile, model: model) }
            PanelRenderer(spec: tile.fixture.spec, store: tile.store, webModel: model.webModel)
                .render(tile.fixture.spec.root)
                        .disabled(tile.lifecycle.taskState != .running)
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
