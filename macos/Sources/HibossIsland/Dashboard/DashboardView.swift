// Unified home workspace for decisions and live task panels.
// Exports: DashboardView with responsive sections and a shared detail inspector.
// Dependencies: SwiftUI, HibossKit, overview snapshots, and attention reply state.

import HibossKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var flow: OptionFlowStore
    @ObservedObject var reply: AttentionReplyState
    @ObservedObject var panels: PanelsModel
    let snapshot: OverviewSnapshot
    let isPreview: Bool
    let onAllDecisions: () -> Void
    let onHistory: () -> Void
    let onSettings: () -> Void
    @State private var selectedDecisionID: MessageID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedDecision: AttentionItem? {
        snapshot.attention.first { $0.id == selectedDecisionID }
    }

    private var showsInspector: Binding<Bool> {
        Binding(get: { selectedDecision != nil || panels.selectedTile != nil }, set: { visible in
            if !visible { selectedDecisionID = nil; panels.closeDetail() }
        })
    }

    var body: some View {
        GeometryReader { geometry in
            workspace(compact: geometry.size.width < 900)
                .inspector(isPresented: inspectorPresentation(compact: geometry.size.width < 900)) {
                    inspector.inspectorColumnWidth(min: 340, ideal: 420, max: 560)
                }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await panels.loadIfNeeded() }
        .onChange(of: panels.selectedTileID) { _, id in
            if id != nil { selectedDecisionID = nil }
        }
        .onChange(of: snapshot.attention.map(\.id)) { _, ids in
            if let selectedDecisionID, !ids.contains(selectedDecisionID) { self.selectedDecisionID = nil }
        }
        .accessibilityIdentifier("dashboard.home")
    }

    @ViewBuilder
    private func workspace(compact: Bool) -> some View {
        if compact && showsInspector.wrappedValue {
            inspector.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    DashboardWorkspaceHeader(snapshot: snapshot,
                        countsAvailable: isPreview || flow.historyState == .loaded || !snapshot.history.isEmpty,
                        isPreview: isPreview, onHistory: onHistory)
                    decisions
                    Divider()
                    DashboardPanelsSection(model: panels)
                }
                .padding(28)
                .frame(maxWidth: 1440, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private func inspectorPresentation(compact: Bool) -> Binding<Bool> {
        Binding(get: { !compact && showsInspector.wrappedValue }, set: { visible in
            if !compact && !visible { showsInspector.wrappedValue = false }
        })
    }

    private var decisions: some View {
        DashboardDecisionsSection(items: snapshot.attention, now: snapshot.now,
            historyState: isPreview ? .loaded : flow.historyState,
            connectionState: isPreview ? .connected : flow.connectionState,
            limit: 3, onSelect: openDecision, onAll: onAllDecisions,
            onRetry: { Task { await flow.refreshHistory() } }, onSettings: onSettings)
    }

    @ViewBuilder
    private var inspector: some View {
        if let selectedDecision {
            DashboardDecisionDetail(item: selectedDecision, now: snapshot.now, flow: flow,
                reply: reply, isPreview: isPreview, onClose: { selectedDecisionID = nil })
        } else if let tile = panels.selectedTile {
            ScrollView { DashboardPanelDetail(tile: tile, model: panels).padding(20) }
        }
    }

    private func openDecision(_ item: AttentionItem) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            panels.closeDetail()
            selectedDecisionID = item.id
        }
    }
}
