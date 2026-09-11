// Main window: unified Dashboard home with decision categories and session drill-down.
// Exports: MainView with persistent Panels state and shared attention drafts.
// Dependencies: SwiftUI, HibossKit, DashboardView, AttentionView, and HistoryView.

import HibossKit
import AppKit
import SwiftUI

struct MainView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var settings: AppSettings
    @ObservedObject var flow: OptionFlowStore
    @ObservedObject var notificationNavigation: MessageNotificationNavigation
    @StateObject private var reply = AttentionReplyState()
    @StateObject private var overviewStore = OverviewStore()
    @StateObject private var panels: PanelsModel
    @State private var destination: OverviewDestination = .dashboard
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showsCompactOverview = false
    @State private var previewHistory = AttentionPreview.historyIfRequested()

    private static let sidebarMinimumWidth: CGFloat = 760

    init(settings: AppSettings, flow: OptionFlowStore,
         notificationNavigation: MessageNotificationNavigation = MessageNotificationNavigation()) {
        self.settings = settings
        self.flow = flow
        self.notificationNavigation = notificationNavigation
        _panels = StateObject(wrappedValue: PanelsModel(configurationProvider: {
            guard let config = settings.activeClientConfig else {
                throw PanelClientError.notConfigured
            }
            return config
        }))
    }

    var body: some View {
        GeometryReader { geometry in
            shell(snapshot: overviewStore.snapshot, compact: geometry.size.width < Self.sidebarMinimumWidth)
            .onAppear { adaptSidebar(to: geometry.size.width) }
            .onChange(of: geometry.size.width) { _, width in adaptSidebar(to: width) }
        }
        .frame(minWidth: 480, minHeight: 400)
        .onAppear { updateOverview() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await panels.load() }
        }
        .onAppear {
            let action = openWindow
            notificationNavigation.openWindow = { action(id: "main") }
        }
        .onChange(of: notificationNavigation.target?.id, initial: true) { _, id in
            guard id != nil else { return }
            destination = .category(.all)
            showsCompactOverview = false
        }
        .sheet(item: $notificationNavigation.target) { target in
            NotificationMessageDetail(messageID: target.id, settings: settings, reply: reply)
        }
        .onChange(of: flow.historyMessages) { updateOverview() }
        .onChange(of: flow.activeMessage) { updateOverview() }
        .onChange(of: settings.activeClientConfig) { Task { await panels.load() } }
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
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .help(destination == .dashboard ? L("Refresh dashboard") : L("Refresh messages"))
                .disabled(flow.historyState == .loading || (destination == .dashboard && panels.isLoading))
            }
        }
    }

    private func overview(_ snapshot: OverviewSnapshot) -> some View {
        OverviewSidebar(snapshot: snapshot, selection: destination,
            historyState: previewHistory == nil ? flow.historyState : .loaded,
            connectionState: previewHistory == nil ? flow.connectionState : .connected,
            onSelect: { destination = $0; showsCompactOverview = false },
            onSettings: { openWindow(id: "settings") },
            onRefresh: refresh)
    }

    private func destinationContent(_ snapshot: OverviewSnapshot) -> some View {
        GeometryReader { geometry in
            if destination == .dashboard {
                DashboardView(flow: flow, reply: reply, panels: panels, snapshot: snapshot,
                    isPreview: previewHistory != nil,
                    onAllDecisions: { destination = .category(.needsYou) },
                    onSettings: { openWindow(id: "settings") })
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

    private func refresh() {
        Task { await flow.refreshHistory() }
        if destination == .dashboard { Task { await panels.load() } }
    }
}
