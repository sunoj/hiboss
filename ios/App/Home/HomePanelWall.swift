// iOS dashboard wall with shared summary cards and native panel detail navigation.
// Exports: HomePanelWall.
// Dependencies: SwiftUI, HibossKit PanelsModel, PanelDashboardCard, and PanelRenderer.

import HibossKit
import SwiftUI

struct HomePanelWall: View {
    @ObservedObject var model: PanelsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Live panels").font(.title2.bold())
                Spacer()
                if model.isDemoMode {
                    Text("Sample data").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("\(model.visibleTiles.count)").font(.headline).foregroundStyle(.secondary)
                }
            }
            PanelWallFilter(model: model)
            if !model.visibleTiles.isEmpty {
                if let failure = model.failureMessage {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }
                wall
            } else if model.isLoading {
                ProgressView("Loading panels…").frame(maxWidth: .infinity, alignment: .leading)
            } else {
                emptyState
            }
        }
        .padding(.horizontal, 16)
        .task { await model.loadIfNeeded() }
        .sheet(isPresented: Binding(
            get: { model.selectedTile != nil },
            set: { if !$0 { model.closeDetail() } }
        )) {
            if let tile = model.selectedTile { HomePanelDetail(tile: tile, model: model) }
        }
    }

    private var emptyState: some View {
        PanelWallEmptyState(model: model)
    }

    private var wall: some View {
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

private struct HomePanelDetail: View {
    let tile: PanelTile
    @ObservedObject var model: PanelsModel
    @ObservedObject private var store: PanelStore

    init(tile: PanelTile, model: PanelsModel) {
        self.tile = tile
        self.model = model
        _store = ObservedObject(wrappedValue: tile.store)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(tile.sourceLabel).font(.callout).foregroundStyle(.secondary)
                    Label(model.freshness(for: tile).title, systemImage: model.freshness(for: tile).symbol)
                        .font(.caption).foregroundStyle(model.freshness(for: tile).color)
                    PanelOutcomeView(tile: tile)
                    PanelQuestionnairesView(tile: tile, panels: model)
                    Menu("Panel actions") { PanelLifecycleMenu(tile: tile, model: model) }
                    PanelRenderer(spec: tile.fixture.spec, store: store, webModel: model.webModel)
                        .disabled(tile.lifecycle.taskState != .running)
                    if let answer = store.submittedAnswerText {
                        Text("Captured submission").font(.headline)
                        if store.submissionWasEdited {
                            Text("The form has changed since this submission.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Text(answer).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                .padding(20)
            }
            .navigationTitle(tile.fixture.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { model.closeDetail() } } }
        }
    }
}
