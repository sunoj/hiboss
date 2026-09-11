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
                PanelWallEmptyState(model: model).frame(minHeight: 180)
            }
        }
        .accessibilityIdentifier("dashboard.panels")
    }
}

struct PanelWall: View {
    @ObservedObject var model: PanelsModel

    var body: some View {
        PanelWallLayout {
            ForEach(model.visibleTiles) { tile in
                PanelDashboardCard(tile: tile, freshness: model.freshness(for: tile), pendingCount: model.pendingCount(for: tile)) { model.open(tile.id) }
                    .contextMenu { PanelLifecycleMenu(tile: tile, model: model) }
                    .layoutValue(key: PanelTileSizeLayoutValueKey.self, value: tile.fixture.spec.tileSize)
                }
            }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            PanelQuestionnairesView(tile: tile, panels: model)
            Menu("Panel actions") { PanelLifecycleMenu(tile: tile, model: model) }
            PanelRenderer(spec: tile.fixture.spec, store: tile.store, webModel: model.webModel)
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
