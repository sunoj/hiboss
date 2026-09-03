// Main HiBoss window: Needs You first, History second.
// Exports: MainView and MainSurface sidebar destinations.
// Dependencies: SwiftUI, AppSettings, OptionFlowStore, AttentionView, HistoryView.

import HibossKit
import SwiftUI

enum MainSurface: String, CaseIterable, Identifiable {
    case attention
    case history

    var id: Self { self }

    var title: String {
        switch self {
        case .attention: L("Needs You")
        case .history: L("History")
        }
    }

    var icon: String {
        switch self {
        case .attention: "bell"
        case .history: "clock"
        }
    }
}

struct MainView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var flow: OptionFlowStore
    @State private var surface: MainSurface = .attention

    var body: some View {
        Group {
            if let preview = AttentionPreview.workspaceIfRequested() {
                preview
            } else {
                liveShell
            }
        }
        .frame(minWidth: 880, minHeight: 560)
    }

    private var liveShell: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let attentionCount = AttentionRanking.items(
                history: flow.historyMessages,
                live: flow.activeMessage,
                now: context.date
            ).count
            NavigationSplitView {
                List(selection: $surface) {
                    Label(MainSurface.attention.title, systemImage: MainSurface.attention.icon)
                        .badge(attentionCount)
                        .tag(MainSurface.attention)
                    Label(MainSurface.history.title, systemImage: MainSurface.history.icon)
                        .tag(MainSurface.history)
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
            } detail: {
                switch surface {
                case .attention:
                    AttentionView(flow: flow)
                case .history:
                    HistoryView(flow: flow)
                }
            }
        }
        .toolbar { mainToolbar }
        .task {
            if flow.historyState == .idle { await flow.refreshHistory() }
        }
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Image(systemName: connectionSymbol)
                .foregroundStyle(
                    flow.connectionState == .connected ? DesignTokens.live : Color.secondary
                )
                .help(flow.connectionState.label)
                .accessibilityLabel(L("Connection: \(flow.connectionState.label)"))

            Button {
                Task { await flow.refreshHistory() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help(L("Refresh messages"))
            .disabled(flow.historyState == .loading)
            .accessibilityLabel(L("Refresh messages"))
        }
    }

    private var connectionSymbol: String {
        switch flow.connectionState {
        case .connected: "antenna.radiowaves.left.and.right"
        case .connecting: "antenna.radiowaves.left.and.right"
        case .failed: "exclamationmark.triangle"
        case .disconnected: "antenna.radiowaves.left.and.right.slash"
        }
    }
}
