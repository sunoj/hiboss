// Embeddable Panels section and detail for the unified macOS dashboard.
// Exports: DashboardPanelsSection, PanelWall, and DashboardPanelDetail.
// Dependencies: SwiftUI and HibossKit panel models, rendering, and lifecycle controls.

import SwiftUI
import HibossKit

struct DashboardPanelsSection: View {
    @ObservedObject var model: PanelsModel
    var sessionID: String? = nil
    private var tiles: [PanelTile] { PanelWall.scopedTiles(model.visibleTiles, sessionID: sessionID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L("Live tasks")).font(.title2.bold())
                Text(verbatim: model.tiles.isEmpty && model.loadState != .loaded
                    ? "—" : tiles.count.formatted())
                    .foregroundStyle(TodayStyle.secondary).monospacedDigit()
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
            }
            PanelWallFilter(model: model)
            if model.isDemoMode {
                Label(L("Sample data · Local preview"), systemImage: "info.circle")
                    .font(.callout).foregroundStyle(TodayStyle.secondary)
            }
            if let failure = model.failureMessage {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(TodayStyle.signal)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("Retry panels")) { Task { await model.load() } }
            }
            if !tiles.isEmpty {
                PanelWall(model: model, sessionID: sessionID)
            } else if !model.isLoading && model.failureMessage == nil {
                if sessionID != nil {
                    Text(L("No panels in this session.")).foregroundStyle(TodayStyle.secondary)
                } else {
                    PanelWallEmptyState(model: model).frame(minHeight: 180)
                }
            }
        }
        .accessibilityIdentifier("dashboard.panels")
    }
}

struct PanelWall: View {
    @ObservedObject var model: PanelsModel
    var sessionID: String? = nil

    static func scopedTiles(_ tiles: [PanelTile], sessionID: String?) -> [PanelTile] {
        guard let sessionID else { return tiles }
        return tiles.filter { $0.metadata?.sessionId == sessionID }
    }

    var body: some View {
        PanelWallLayout {
            ForEach(Self.scopedTiles(model.visibleTiles, sessionID: sessionID)) { tile in
                PanelDashboardCard(tile: tile, freshness: model.freshness(for: tile),
                    pendingCount: model.pendingCount(for: tile)) { model.open(tile.id) }
                    .background(TodayStyle.surface, in: RoundedRectangle(cornerRadius: 24))
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
                Button(L("Close panel"), systemImage: "xmark") { model.closeDetail() }
                Spacer()
                PanelFreshnessLabel(freshness: model.freshness(for: tile))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(tile.fixture.title).font(.title.bold())
                Text(tile.sourceLabel).font(.callout).foregroundStyle(TodayStyle.secondary)
            }
            PanelOutcomeView(tile: tile)
            PanelQuestionnairesView(tile: tile, panels: model)
            Menu(L("Panel actions")) { PanelLifecycleMenu(tile: tile, model: model) }
            PanelRenderer(spec: tile.fixture.spec, store: tile.store, webModel: model.webModel)
                        .disabled(tile.lifecycle.taskState != .running)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let answer = tile.store.submittedAnswerText {
                Text(L("Captured submission")).font(.headline).padding(.top, 10)
                if tile.store.submissionWasEdited {
                    Text(L(
                        "Form edited since submission; this is the previous answer, not the current draft."))
                        .font(.callout).foregroundStyle(TodayStyle.secondary)
                }
                Text(answer).font(.body.monospaced()).textSelection(.enabled)
                    .foregroundStyle(TodayStyle.secondary)
            }
        }
    }
}
