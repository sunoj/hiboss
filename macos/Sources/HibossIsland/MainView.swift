// Main window: Today, Box, Progress, and session threads with native sidebar navigation.
// Exports: MainView with persistent Panels state and shared attention drafts.
// Dependencies: SwiftUI, HibossKit, TodayView, AttentionView, and HistoryView.

import HibossKit
import AppKit
import SwiftUI

struct MainView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var settings: AppSettings
    @ObservedObject var flow: OptionFlowStore
    @ObservedObject var notificationNavigation: MessageNotificationNavigation
    @ObservedObject var joinRequests: JoinRequestsModel
    @StateObject private var reply = AttentionReplyState()
    @StateObject private var overviewStore = OverviewStore()
    @StateObject private var panels: PanelsModel
    @StateObject private var box: BoxBrowserStore
    @StateObject private var boxMedia: BoxBrowserMedia
    @StateObject private var sessionBox: BoxBrowserStore
    private let previewSessions: [ProjectSession]?
    @State private var destination: OverviewDestination = .today
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showsCompactOverview = false
    @State private var previewHistory = AttentionPreview.historyIfRequested()

    private static let sidebarMinimumWidth: CGFloat = 760

    init(settings: AppSettings, flow: OptionFlowStore,
         notificationNavigation: MessageNotificationNavigation = MessageNotificationNavigation(),
         joinRequests: JoinRequestsModel = JoinRequestsModel { nil },
         initialDestination: OverviewDestination = .today,
         previewHistory: [HistoryMessage]? = AttentionPreview.historyIfRequested(),
         previewSessions: [ProjectSession]? = nil,
         boxProvider: BoxBrowserStore.Provider? = nil,
         panelsModel: PanelsModel? = nil) {
        self.settings = settings
        self.previewSessions = previewSessions
        _previewHistory = State(initialValue: previewHistory)
        _destination = State(initialValue: initialDestination)
        self.flow = flow
        self.notificationNavigation = notificationNavigation
        self.joinRequests = joinRequests
        let provider: BoxBrowserStore.Provider = boxProvider ?? {
            settings.activeClientConfig.map { HibossAPI(config: $0) }
        }
        _box = StateObject(wrappedValue: BoxBrowserStore(apiProvider: provider))
        _boxMedia = StateObject(wrappedValue: BoxBrowserMedia(apiProvider: provider))
        _sessionBox = StateObject(wrappedValue: BoxBrowserStore(apiProvider: provider))
        _panels = StateObject(wrappedValue: panelsModel ?? PanelsModel(configurationProvider: {
            guard let config = settings.activeClientConfig else {
                throw PanelClientError.notConfigured
            }
            return config
        }))
    }

    private var navigationContent: some View {
        GeometryReader { geometry in
            shell(snapshot: overviewStore.snapshot, compact: geometry.size.width < Self.sidebarMinimumWidth)
            .onAppear { adaptSidebar(to: geometry.size.width) }
            .onChange(of: geometry.size.width) { _, width in adaptSidebar(to: width) }
        }
        .frame(minWidth: 480, minHeight: 400)
        .onAppear { updateOverview() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            if previewHistory == nil { refresh() }
        }
        .onChange(of: notificationNavigation.target?.id, initial: true) { _, id in
            guard id != nil else { return }
            destination = .category(.all)
            showsCompactOverview = false
        }
        .onChange(of: notificationNavigation.deviceRequestsFocus?.id, initial: true) { _, id in
            guard id != nil else { return }
            destination = .deviceRequests
            showsCompactOverview = false
        }
        .sheet(item: $notificationNavigation.target) { target in
            NotificationMessageDetail(messageID: target.id, settings: settings, reply: reply,
                onReply: flow.answer)
        }
    }

    var body: some View {
        observedContent
        .onChange(of: settings.activeClientConfig) {
            box.reset()
            sessionBox.reset()
            boxMedia.reset()
            Task {
                await panels.load()
                if destination == .box { await box.refresh() }
            }
        }
        .task { if flow.historyState == .idle { await flow.refreshHistory() } }
    }

    private var observedContent: some View {
        navigationContent
        .onChange(of: flow.historyMessages) { updateOverview() }
        .onChange(of: flow.activeMessage) { updateOverview() }
        .onChange(of: flow.connectionState) { updateOverview() }
        .onChange(of: flow.historyState) { updateOverview() }
        .onChange(of: flow.replyFeedback) { updateOverview() }
        .onChange(of: panels.hasCompleteQuestionnaires) { updateOverview() }
        .onChange(of: panels.pendingQuestionnaires) { updateOverview() }
    }

    private func updateOverview() {
        let history = previewHistory ?? flow.historyMessages
        let now = Date.now
        let health = previewHistory != nil ? TodayHealth.live(checkedAt: now)
            : TodayProjection.health(connection: flow.connectionState,
                history: flow.historyState, checkedAt: now)
        let coverage = previewHistory != nil || (TodayProjection.coverage(history: history,
            state: flow.historyState) && panels.hasCompleteQuestionnaires
            && !panels.pendingQuestionnaires.contains(where: \.blocking))
        overviewStore.update(history: history, live: flow.activeMessage, now: now,
            health: health, coverageComplete: coverage,
            withdrawn: TodayProjection.withdrawn(feedback: flow.replyFeedback),
            requiredInputs: previewHistory ?? [])
    }

    private func shell(snapshot: OverviewSnapshot, compact: Bool) -> some View {
        windowContent(snapshot: snapshot, compact: compact)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Image(systemName: flow.connectionState == .connected
                    ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(flow.connectionState == .connected ? DesignTokens.live : .secondary)
                    .help(flow.connectionState.label)
                Button(action: refresh) { Image(systemName: "arrow.clockwise") }
                    .help(refreshHelp)
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(destination == .box ? box.isLoading
                        : flow.historyState == .loading || (destination == .today && panels.isLoading))
            }
        }
    }

    @ViewBuilder
    private func windowContent(snapshot: OverviewSnapshot, compact: Bool) -> some View {
        messageShell(snapshot: snapshot, compact: compact)
    }

    private func messageShell(snapshot: OverviewSnapshot, compact: Bool) -> some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            overview(snapshot)
                .navigationSplitViewColumnWidth(min: 220, ideal: 244, max: 280)
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
        }
    }

    private var refreshHelp: String {
        if destination == .box { return L("Refresh Box") }
        switch destination {
        case .today: return L("Refresh Today")
        case .deviceRequests: return L("Refresh device requests")
        default: return L("Refresh messages")
        }
    }

    private func overview(_ snapshot: OverviewSnapshot) -> some View {
        OverviewSidebar(snapshot: snapshot, selection: destination,
            historyState: previewHistory == nil ? flow.historyState : .loaded,
            connectionState: previewHistory == nil ? flow.connectionState : .connected,
            deviceRequestCount: joinRequests.pendingCount,
            onSelect: {
                destination = $0
                showsCompactOverview = false
                if $0 == .box {
                    box.project = nil
                    Task { await box.refresh() }
                }
            },
            onSettings: { openWindow(id: "settings") },
            onRefresh: refresh)
    }

    private func destinationContent(_ snapshot: OverviewSnapshot) -> some View {
        GeometryReader { geometry in
            if destination == .today {
                TodayView(snapshot: snapshot, reply: reply, panels: panels, isPreview: previewHistory != nil,
                    onChoose: flow.answer,
                    onSession: { destination = .session($0) })
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            } else if case let .session(id) = destination {
                SessionView(context: SessionContext(id: id, snapshot: snapshot,
                    inventory: previewSessions ?? flow.projectSessions), flow: flow, reply: reply,
                    panels: panels, box: sessionBox, media: boxMedia, isPreview: previewHistory != nil,
                    onBox: { project in
                        box.author = .all
                        box.kind = nil
                        box.query = ""
                        box.project = project
                        destination = .box
                    }, onSession: { destination = .session($0) })
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            } else if destination == .box {
                BoxBrowserView(store: box, media: boxMedia)
            } else if destination == .progress {
                ProgressWorkspace(model: panels)
            } else if destination == .deviceRequests {
                DeviceRequestsView(model: joinRequests, focus: $notificationNavigation.deviceRequestsFocus,
                    onSettings: { openWindow(id: "settings") })
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            } else {
                VStack(spacing: 0) {
                    OverviewContentHeader(destination: destination, snapshot: snapshot,
                        countsAvailable: previewHistory != nil || flow.historyState == .loaded
                            || !snapshot.history.isEmpty)
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
                items: snapshot.attention.filter { item in
                    snapshot.messages(for: destination).contains { $0.id == item.id }
                },
                now: snapshot.now)
        } else {
            HistoryView(flow: flow, snapshot: snapshot, scope: destination, reply: reply)
        }
    }

    private func adaptSidebar(to width: CGFloat) {
        columnVisibility = width < Self.sidebarMinimumWidth ? .detailOnly : .all
    }

    private func refresh() {
        if destination == .box {
            Task { await box.refresh() }
            return
        }
        if destination == .deviceRequests { Task { await joinRequests.refresh() } }
        if case .session = destination, sessionBox.project != nil { Task { await sessionBox.refresh() } }
        Task { await flow.refreshHistory() }
        if destination == .today || destination == .progress { Task { await panels.load() } }
    }
}
