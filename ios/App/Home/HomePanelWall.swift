// iOS dashboard wall with shared summary cards and native panel detail navigation.
// Exports: HomePanelWall, shown by Home only when at least one tile exists in any state.
// Exports HomePanelDetail for Home's persistent sheet, including notification routes.
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
                    Text("Sample data").font(.caption).foregroundStyle(Theme.ink2)
                } else {
                    Text(model.visibleTiles.count, format: .number).font(.headline).foregroundStyle(
                        Theme.ink2)
                }
            }
            PanelWallFilter(model: model)
            if !model.visibleTiles.isEmpty {
                if let failure = model.failureMessage {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(Theme.warn)
                }
                wall
            } else if model.isLoading {
                PendingStateView(title: String(localized: "Loading panels…"),
                                 onRetry: { await model.retryLoading() })
            } else {
                emptyState
            }
        }
        .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        PanelWallEmptyState(model: model)
    }

    private var wall: some View {
        PanelWallLayout {
            ForEach(model.visibleTiles) { tile in
                PanelDashboardCard(
                    tile: tile, freshness: displayedPanelFreshness(tile, model: model),
                    pendingCount: model.pendingCount(for: tile)
                ) { model.open(tile.id) }
                    .contextMenu { PanelLifecycleMenu(tile: tile, model: model) }
                    .layoutValue(key: PanelTileSizeLayoutValueKey.self, value: tile.fixture.spec.tileSize)
                }
            }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HomePanelDetail: View {
    let tile: PanelTile
    @ObservedObject var model: PanelsModel
    @ObservedObject private var store: PanelStore
    @Environment(\.openConnectionSettings) private var openSettings
    @State private var preferenceConfirmed = false

    init(tile: PanelTile, model: PanelsModel) {
        self.tile = tile
        self.model = model
        _store = ObservedObject(wrappedValue: tile.store)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(verbatim: tile.sourceLabel).font(.callout).foregroundStyle(Theme.ink2)
                    PanelFreshnessLabel(freshness: displayedPanelFreshness(tile, model: model))
                        .font(.caption)
                    PanelPendingNotice(freshness: displayedPanelFreshness(tile, model: model),
                                       retry: { await model.retryLoading() })
                    PanelOutcomeView(tile: tile)
                    PanelQuestionnairesView(tile: tile, panels: model)
                    panelActions
                    PanelRenderer(spec: tile.fixture.spec, store: store, webModel: model.webModel)
                        .disabled(tile.lifecycle.taskState != .running)
                    if let answer = store.submittedAnswerText {
                        Text("Captured submission").font(.headline)
                        if store.submissionWasEdited {
                            Text("The form has changed since this submission.")
                                .font(.callout).foregroundStyle(Theme.ink2)
                        }
                        Text(verbatim: answer).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                .padding(20)
            }
            .navigationTitle(Text(verbatim: tile.fixture.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { model.closeDetail() } }
            }
        }
    }

    private var panelActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu { PanelLifecycleMenu(tile: tile, model: model) } label: {
                HStack {
                    Text("Panel actions")
                    if model.pendingPreferenceIDs.contains(tile.id) { DelayedProgressView() }
                }.frame(minHeight: 44)
            }.disabled(model.pendingPreferenceIDs.contains(tile.id))
                .accessibilityLabel("Panel actions")
            if model.pendingPreferenceIDs.contains(tile.id) {
                PendingStateView(title: String(localized: "Updating panel…"), onSettings: openSettings)
            }
            if preferenceConfirmed { Text("Panel updated.").font(.hbCallout).foregroundStyle(Theme.ink2) }
            if let error = model.preferenceError {
                Label { Text(verbatim: error) } icon: { Image(systemName: "exclamationmark.triangle") }
                    .foregroundStyle(Theme.warn).font(.hbCallout)
            }
        }.onChange(of: model.pendingPreferenceIDs) { previous, current in
            if current.contains(tile.id) { preferenceConfirmed = false }
            else if previous.contains(tile.id) { preferenceConfirmed = model.preferenceError == nil }
        }
    }
}
