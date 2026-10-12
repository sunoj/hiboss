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
    @ObservedObject private var requiredInputs: RequiredInputStore
    @StateObject private var overviewStore = OverviewStore()
    @StateObject private var panels: PanelsModel
    @StateObject private var box: BoxBrowserStore
    @StateObject private var progress: ProgressFeedStore
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
         overviewStore: OverviewStore = OverviewStore(),
         requiredInputs: RequiredInputStore = RequiredInputStore(),
         initialDestination: OverviewDestination = .today,
         previewHistory: [HistoryMessage]? = AttentionPreview.historyIfRequested(),
         previewSessions: [ProjectSession]? = nil,
         boxProvider: BoxBrowserStore.Provider? = nil,
         boxStore: BoxBrowserStore? = nil, boxMedia: BoxBrowserMedia? = nil,
         progressProvider: ProgressFeedStore.Provider? = nil,
         progressStore: ProgressFeedStore? = nil,
         panelsModel: PanelsModel? = nil) {
        self.requiredInputs = requiredInputs
        _overviewStore = StateObject(wrappedValue: overviewStore)
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
        _box = StateObject(wrappedValue: boxStore ?? BoxBrowserStore(apiProvider: provider))
        _boxMedia = StateObject(wrappedValue: boxMedia ?? BoxBrowserMedia(apiProvider: provider))
        _sessionBox = StateObject(wrappedValue: BoxBrowserStore(apiProvider: provider))
        _progress = StateObject(wrappedValue: progressStore ?? ProgressFeedStore(
            apiProvider: progressProvider ?? {
                settings.activeClientConfig.map { HibossAPI(config: $0) }
            }))
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
        .onChange(of: panels.selectedTileID, initial: true) { _, id in
            guard id != nil, destination == .progress else { return }
            destination = .today
            showsCompactOverview = false
        }
        .sheet(item: $notificationNavigation.target) { target in
            NotificationMessageDetail(messageID: target.id, settings: settings, reply: reply,
                overview: overviewStore,
                onReply: flow.answer)
        }
    }

    var body: some View {
        observedContent
        .environment(\.projectSessions, previewSessions ?? flow.projectSessions)
        .environment(\.agentAvatars, previewHistory == nil ? flow.agentAvatars : AttentionPreview.avatars)
        .onChange(of: settings.activeClientConfig) {
            panels.connectionDidChange()
            box.reset()
            progress.reset()
            sessionBox.reset()
            boxMedia.reset()
            Task {
                await panels.load()
                if destination == .box { await box.refresh() }
                if destination == .progress { await progress.refresh() }
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
        .onChange(of: panels.hasDisplayCoverage) { updateOverview() }
        .onChange(of: panels.pendingQuestionnaires) { updateOverview() }
    }

    private func updateOverview() {
        guard let history = previewHistory else {
            overviewStore.setQuestionnaireCoverage(panels.hasDisplayCoverage
                && !panels.pendingQuestionnaires.contains(where: \.blocking))
            return
        }
        let now = Date.now
        overviewStore.update(history: history, live: nil, now: now,
            health: .live(checkedAt: now), coverageComplete: true,
            requiredInputs: history, requiredInputLoaded: true)
    }

    private func shell(snapshot: OverviewSnapshot, compact: Bool) -> some View {
        messageShell(snapshot: snapshot, compact: compact)
            .modifier(WorkspaceToolbar(flow: flow, destination: destination, onRefresh: refresh))
    }

    private func messageShell(snapshot: OverviewSnapshot, compact: Bool) -> some View {
        Group {
            if destination == .box && !(compact && showsCompactOverview) {
                BoxBrowserView(store: box, media: boxMedia, sidebar: AnyView(overview(snapshot)))
            } else {
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

    private func overview(_ snapshot: OverviewSnapshot) -> some View {
        OverviewSidebar(snapshot: snapshot, selection: destination,
            historyState: previewHistory == nil ? flow.historyState : .loaded,
            connectionState: previewHistory == nil ? flow.connectionState : .connected,
            hasLoadedHistory: previewHistory != nil || flow.historyLoadedAt != nil,
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
                    isRefreshing: flow.isRefreshingHistory || panels.isRefreshing
                        || requiredInputs.state.refreshing,
                    onChoose: answer,
                    onSession: { destination = .session($0) })
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            } else if case let .session(id) = destination {
                sessionSurface(id: id, snapshot: snapshot)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            } else if destination == .progress {
                ProgressWorkspace(store: progress)
            } else if destination == .deviceRequests {
                DeviceRequestsView(model: joinRequests, focus: $notificationNavigation.deviceRequestsFocus,
                    onSettings: { openWindow(id: "settings") })
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            } else {
                VStack(spacing: 0) {
                    OverviewContentHeader(destination: destination, snapshot: snapshot,
                        countsAvailable: previewHistory != nil || flow.historyLoadedAt != nil
                            || !snapshot.history.isEmpty)
                    Divider()
                    messageSurface(snapshot)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
        }
    }

    private func sessionSurface(id: String, snapshot: OverviewSnapshot) -> some View {
        SessionView(context: SessionContext(id: id, snapshot: snapshot,
            inventory: previewSessions ?? flow.projectSessions), flow: flow, reply: reply,
            panels: panels, box: sessionBox, media: boxMedia, isPreview: previewHistory != nil,
            onChoose: answer,
            onBox: { project in
                box.author = .all
                box.kind = nil
                box.query = ""
                box.project = project
                destination = .box
            }, onSession: { destination = .session($0) })
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
                now: snapshot.now, answerability: snapshot.answerability, onChoose: answer)
        } else {
            HistoryView(flow: flow, snapshot: snapshot, scope: destination, onChoose: answer, reply: reply)
        }
    }

    private func adaptSidebar(to width: CGFloat) {
        columnVisibility = width < Self.sidebarMinimumWidth ? .detailOnly : .all
    }

    private func answer(_ text: String, for id: MessageID) async -> ReplyFeedback? {
        await overviewStore.answer(text, for: id, using: flow.answer)
    }

    private func refresh() {
        if destination == .progress {
            Task { await progress.refresh() }
            return
        }
        if destination == .box {
            Task { await box.refresh() }
            return
        }
        if destination == .deviceRequests { Task { await joinRequests.refresh() } }
        if case .session = destination, sessionBox.project != nil { Task { await sessionBox.refresh() } }
        requiredInputs.refresh()
        Task { await flow.refreshHistory() }
        if destination == .today { Task { await panels.load() } }
    }
}
