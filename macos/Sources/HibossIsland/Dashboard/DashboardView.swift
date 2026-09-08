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
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    sections(wide: geometry.size.width >= 980)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .inspector(isPresented: showsInspector) {
            inspector.inspectorColumnWidth(min: 340, ideal: 420, max: 560)
        }
        .task { await panels.loadIfNeeded() }
        .onChange(of: panels.selectedTileID) { _, id in
            if id != nil { selectedDecisionID = nil }
        }
        .onChange(of: snapshot.attention.map(\.id)) { _, ids in
            if let selectedDecisionID, !ids.contains(selectedDecisionID) { self.selectedDecisionID = nil }
        }
        .accessibilityIdentifier("dashboard.home")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Dashboard")).font(.largeTitle.bold())
            Text(L("Decisions and live panels."))
                .font(.callout).foregroundStyle(.secondary)
            if isPreview {
                Label(L("Sample decisions · Local preview"), systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func sections(wide: Bool) -> some View {
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 28))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 24))
        return layout {
            DashboardDecisionsSection(items: snapshot.attention, now: snapshot.now,
                historyState: isPreview ? .loaded : flow.historyState,
                connectionState: isPreview ? .connected : flow.connectionState,
                limit: wide ? 5 : 2, onSelect: openDecision, onAll: onAllDecisions,
                onRetry: { Task { await flow.refreshHistory() } }, onSettings: onSettings)
                .frame(width: wide ? 300 : nil, alignment: .topLeading)
            DashboardPanelsSection(model: panels)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
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
