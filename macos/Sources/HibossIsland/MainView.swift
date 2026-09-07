// Main window: category overview and sessions beside the selected message surface.
// Exports: MainView with adaptive overview navigation and shared attention drafts.
// Dependencies: SwiftUI, HibossKit, OverviewSnapshot, AttentionView, HistoryView.

import HibossKit
import SwiftUI

struct MainView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var settings: AppSettings
    @ObservedObject var flow: OptionFlowStore
    @StateObject private var reply = AttentionReplyState()
    @StateObject private var overviewStore = OverviewStore()
    @State private var destination: OverviewDestination = ProcessInfo.processInfo.environment["HIBOSS_PANELS_DEMO"] == "1" ? .panels : .category(.needsYou)
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showsCompactOverview = false
    @State private var previewHistory = AttentionPreview.historyIfRequested()

    private static let sidebarMinimumWidth: CGFloat = 760

    var body: some View {
        GeometryReader { geometry in
            shell(snapshot: overviewStore.snapshot, compact: geometry.size.width < Self.sidebarMinimumWidth)
            .onAppear { adaptSidebar(to: geometry.size.width) }
            .onChange(of: geometry.size.width) { _, width in adaptSidebar(to: width) }
        }
        .frame(minWidth: 480, minHeight: 400)
        .onAppear { updateOverview() }
        .onChange(of: flow.historyMessages) { updateOverview() }
        .onChange(of: flow.activeMessage) { updateOverview() }
        .task { if flow.historyState == .idle { await flow.refreshHistory() } }
    }

    private func updateOverview() {
        overviewStore.update(history: previewHistory ?? flow.historyMessages, live: flow.activeMessage)
    }

    private func shell(snapshot: OverviewSnapshot, compact: Bool) -> some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            overview(snapshot)
                .navigationSplitViewColumnWidth(min: 280, ideal: 300, max: 340)
        } detail: {
            if compact && showsCompactOverview {
                overview(snapshot).navigationTitle(L("Overview"))
            } else {
                destinationContent(snapshot)
                    .navigationTitle(snapshot.title(for: destination))
            }
        }
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if compact {
                    Button {
                        showsCompactOverview.toggle()
                    } label: {
                        Label(L("Overview"), systemImage: "square.grid.2x2")
                    }
                    .accessibilityIdentifier("overview.toggle")
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Image(systemName: flow.connectionState == .connected
                    ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(flow.connectionState == .connected ? DesignTokens.live : .secondary)
                    .help(flow.connectionState.label)
                Button { Task { await flow.refreshHistory() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(L("Refresh messages")).disabled(flow.historyState == .loading)
            }
        }
    }

    private func overview(_ snapshot: OverviewSnapshot) -> some View {
        OverviewSidebar(snapshot: snapshot, selection: destination,
            historyState: previewHistory == nil ? flow.historyState : .loaded,
            connectionState: previewHistory == nil ? flow.connectionState : .connected,
            onSelect: { destination = $0; showsCompactOverview = false },
            onSettings: { openWindow(id: "settings") },
            onRefresh: { Task { await flow.refreshHistory() } })
    }

    private func destinationContent(_ snapshot: OverviewSnapshot) -> some View {
        GeometryReader { geometry in
            if destination == .panels {
                PanelsView()
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            } else {
                VStack(spacing: 0) {
                    OverviewContentHeader(destination: destination, snapshot: snapshot,
                        countsAvailable: previewHistory != nil || flow.historyState == .loaded || !snapshot.history.isEmpty)
                    Divider()
                    messageSurface(snapshot)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
        }
    }

    @ViewBuilder
    private func messageSurface(_ snapshot: OverviewSnapshot) -> some View {
        if snapshot.history.isEmpty, flow.connectionState == .disconnected, previewHistory == nil {
            ContentUnavailableView {
                Label(L("Connect to HiBoss"), systemImage: "antenna.radiowaves.left.and.right.slash")
            } description: {
                Text(L("Connect to receive agent messages."))
            } actions: {
                Button(L("Settings")) { openWindow(id: "settings") }
            }
        } else if case let .category(category) = destination, category.isAttention {
            AttentionView(flow: flow, reply: reply, category: category,
                items: snapshot.messages(for: destination).map(AttentionItem.init(message:)), now: snapshot.now)
        } else {
            HistoryView(flow: flow, snapshot: snapshot, scope: destination, reply: reply)
        }
    }

    private func adaptSidebar(to width: CGFloat) {
        columnVisibility = width < Self.sidebarMinimumWidth ? .detailOnly : .all
    }
}
