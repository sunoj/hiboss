// iOS dashboard wall with shared summary cards and native panel detail navigation.
// Exports: HomePanelWall.
// Dependencies: SwiftUI, HibossKit PanelsModel, PanelDashboardCard, and PanelRenderer.

import HibossKit
import SwiftUI

struct HomePanelWall: View {
    @ObservedObject var model: PanelsModel
    @State private var measuredWidth: CGFloat = 320

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
        VStack(alignment: .leading, spacing: 8) {
            Label(model.failureMessage == nil ? "No panels yet" : "Panels unavailable",
                  systemImage: model.failureMessage == nil ? "rectangle.stack" : "wifi.exclamationmark")
                .font(.headline)
            Text(model.failureMessage ?? "Published agent panels appear here.")
                .font(.callout).foregroundStyle(.secondary)
            Button(model.failureMessage == nil ? "Refresh" : "Retry") { Task { await model.load() } }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var wall: some View {
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
            .onChange(of: proxy.size.width) { measuredWidth = $0 }
        }
        .frame(height: model.wallHeight(of: model.positions(for: measuredWidth)))
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
                    Menu("Panel actions") { PanelLifecycleMenu(tile: tile, model: model) }
                    PanelRenderer(spec: tile.fixture.spec, store: store, webModel: model.webModel)
                        .render(tile.fixture.spec.root)
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
