// App shell: native tabs, one message surface, and notification deep-links.
// Exports: RootTabView switching Home / Activity / Progress / Settings.
// Dependencies: SwiftUI, HibossKit, the feature views, AppRouter, DemoLaunchRoute.

import HibossKit
import SwiftUI

struct RootTabView: View {
    @ObservedObject var inbox: InboxStore
    @ObservedObject var connection: ConnectionStore
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var progress: ProgressFeedStore
    @StateObject private var panels: PanelsModel
    @StateObject private var joinRequests: JoinRequestsModel
    @State private var joinRequestTarget: JoinRequestTarget?
    @ObservedObject private var router = AppRouter.shared
    @Environment(\.scenePhase) private var scenePhase

    /// Tab indices are referenced from playback gating and demo routing, so they are
    /// named rather than written as literals — renumbering silently broke video
    /// autoplay once, by leaving it pointed at whichever tab had inherited the index.
    private static let homeTab = 0
    private static let activityTab = 1
    private static let progressTab = 3

    @State private var tab = ProcessInfo.processInfo.environment["HIBOSS_TAB"] == "progress"
        ? Self.progressTab
        : Self.homeTab
    @State private var homePath = NavigationPath()
    @State private var activityPath = NavigationPath()
    @State private var activitySection = ActivitySection.sessions
    @State private var panelRouteNote: String?

    init(inbox: InboxStore, connection: ConnectionStore,
         preferences: PreferencesStore, progress: ProgressFeedStore) {
        self.inbox = inbox
        self.connection = connection
        self.preferences = preferences
        self.progress = progress
        let panelAPI: (any PanelsServing)? = isDemoMode ? DemoPanelServices.make() : nil
        _panels = StateObject(wrappedValue: PanelsModel(api: panelAPI, configurationProvider: {
            guard let config = connection.config else { throw PanelClientError.notConfigured }
            return config
        }))
        _joinRequests = StateObject(wrappedValue: JoinRequestsModel { () -> (any JoinRequestServing)? in
            isDemoMode ? DemoJoinRequestsAPI.shared : connection.makeAPI()
        })
    }

    private var sessionStreamAPI: (any SessionStreamServing)? {
        if isDemoMode { return DemoBossAPI() }
        return connection.makeAPI()
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            homeTabView
            activityTabView
            progressTabView
            settingsTabView
        }
        .environment(\.openConnectionSettings, {
            panels.closeDetail()
            tab = 5
        })
        .safeAreaInset(edge: .bottom) {
            if let confirmation = inbox.replyConfirmation {
                Label { Text(verbatim: confirmation) } icon: { Image(systemName: "checkmark.circle") }
                    .font(.hbCallout).foregroundStyle(Theme.positive)
                    .padding(8).frame(maxWidth: .infinity).background(.bar)
                    .accessibilityIdentifier("reply-confirmation")
            }
        }
        .task(id: inbox.replyConfirmation) {
            guard inbox.replyConfirmation != nil else { return }
            do { try await Task.sleep(for: .seconds(3)) }
            catch { return }
            inbox.replyConfirmation = nil
        }
    }

    private var routedTabs: some View {
        tabs
        .task(id: router.pendingMessageID) { await openPendingMessage() }
        .onChange(of: router.pendingJoinRequest, initial: true) { openPendingJoinRequest() }
        .sheet(item: $joinRequestTarget) { target in
            NavigationStack { JoinRequestReviewView(requestID: target.id, model: joinRequests) }
        }
        .onChange(of: connection.config) {
            panels.connectionDidChange()
            joinRequests.reset()
            Task { await joinRequests.refresh() }
        }
        .task { await joinRequests.refresh() }
        .task(id: router.pendingPanel) { await openPendingPanel() }
        .alert("Panel unavailable", isPresented: Binding(
            get: { panelRouteNote != nil }, set: { if !$0 { panelRouteNote = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: panelRouteNote ?? "")
        }
    }

    var body: some View {
        routedTabs
        .onChange(of: scenePhase) { _, phase in
            // iOS drops the SSE while backgrounded; on return, reload history so
            // decisions that arrived (or resolved elsewhere) meanwhile show up.
            if phase == .active {
                inbox.refreshHistory()
                // A 403 is final for this connection; only pull-to-refresh asks again.
                if !joinRequests.isForbidden { Task { await joinRequests.refresh() } }
            }
            ProgressVideoPlayback.shared.sceneActive = phase == .active
        }
        .onChange(of: tab) { _, new in
            ProgressVideoPlayback.shared.feedVisible = new == Self.progressTab
            if new == Self.progressTab { Task { await progress.refresh() } }
        }
        .onAppear { applyDemoRoute() }
    }

    private var homeTabView: some View {
        NavigationStack(path: $homePath) {
            HomeView(
                inbox: inbox,
                sessionAPI: sessionStreamAPI,
                panels: panels
            )
            .safeAreaInset(edge: .bottom) {
                if router.pendingPanel != nil {
                    PendingStateView(title: String(localized: "Opening panel…"),
                                     onRetry: { await openPendingPanel() })
                        .padding(12).background(.bar)
                }
            }
        }
        .tabItem { Label("Home", systemImage: "house") }
        .tag(Self.homeTab)
    }

    private var activityTabView: some View {
        NavigationStack(path: $activityPath) {
            ActivityView(store: inbox, section: $activitySection, connection: connection)
                .navigationDestination(for: MessageID.self) { MessageDetailView(store: inbox, messageID: $0) }
                .navigationDestination(for: SessionRoute.self) {
                    SessionMessagesView(route: $0, api: sessionStreamAPI, store: inbox)
                }
                .navigationDestination(for: ResolvedRoute.self) { _ in ResolvedDecisionsView(store: inbox) }
        }
        .tabItem { Label("Activity", systemImage: "bubble.left.and.bubble.right") }
        .tag(Self.activityTab)
    }

    private var progressTabView: some View {
        NavigationStack { ProgressFeedView(store: progress) }
            .tabItem { Label("Progress", systemImage: "calendar.day.timeline.leading") }
            .tag(Self.progressTab)
    }

    private var settingsTabView: some View {
        NavigationStack {
            SettingsView(
                connection: connection,
                connectionState: inbox.connectionState,
                prefs: preferences,
                joinRequests: joinRequests,
                onReconnect: reconnect,
                onDecisionAlertsChanged: { inbox.setDecisionAlertsEnabled($0) }
            )
        }
        .tabItem { Label("Settings", systemImage: "gearshape") }
        .tag(5)
    }

    /// A tapped join-request push opens its sheet over whichever tab is showing.
    private func openPendingJoinRequest() {
        guard let target = router.takeJoinRequest() else { return }
        joinRequestTarget = target
    }

    private func reconnect() {
        guard let api = connection.makeAPI() else { return }
        inbox.start(api: api)
        progress.start(api: api)
        Task {
            await preferences.load(api: api)
            inbox.setDecisionAlertsEnabled(preferences.decisionAlerts)
        }
    }

    /// Opens cached snapshot or alert text immediately. Alert-only previews refresh
    /// in the background; payloads without either briefly wait for the restored API.
    private func openPendingMessage() async {
        guard let route = router.pendingMessage else { return }
        if let cached = route.cachedMessage {
            inbox.cacheMessage(cached.detail)
        } else {
            for _ in 0..<AppConstants.API.notificationReadinessChecks where !inbox.isReady {
                try? await Task.sleep(for: AppConstants.API.notificationReadinessDelay)
                if Task.isCancelled { return }
            }
        }
        await Task.yield()
        guard !Task.isCancelled else { return }
        tab = Self.activityTab
        activitySection = .messages
        activityPath = NavigationPath([route.messageID])
        router.finishOpening(route.messageID)
        if route.cachedMessage?.requiresRefresh == true {
            Task { await refreshNotificationPreview(route.messageID) }
        }
    }

    private func openPendingPanel() async {
        guard let route = router.pendingPanel else { return }
        tab = Self.homeTab
        homePath = NavigationPath()
        panels.closeDetail()
        panelRouteNote = nil
        if !panels.tiles.contains(where: { $0.id == route.panelID }) {
            for _ in 0..<AppConstants.API.notificationReadinessChecks where connection.config == nil {
                try? await Task.sleep(for: AppConstants.API.notificationReadinessDelay)
                if Task.isCancelled { return }
            }
        }
        let opened = await panels.openWhenLoaded(route.panelID)
        guard !Task.isCancelled, router.pendingPanel == route else { return }
        if !opened {
            panels.section = .needsInput
            panelRouteNote = String(
                localized:
            "Couldn't open this panel. Showing Needs input so you can find unanswered questions or refresh."
            )
        }
        router.finishOpening(route)
    }

    private func refreshNotificationPreview(_ messageID: MessageID) async {
        for _ in 0..<AppConstants.API.notificationReadinessChecks where !inbox.isReady {
            try? await Task.sleep(for: AppConstants.API.notificationReadinessDelay)
        }
        guard inbox.isReady else { return }
        _ = await inbox.loadMessage(messageID)
    }

    /// Screenshot / demo deep-links: open a message or a session thread.
    private func applyDemoRoute() {
        switch DemoLaunchRoute.resolve() {
        case .none:
            break
        case .open(let id):
            tab = Self.activityTab
            activitySection = .messages
            activityPath = NavigationPath([id])
        case .notification(let id):
            let detail = DemoBossAPI().messageDetail(for: id)
            let cached = detail.map { PushCachedMessage(detail: $0, requiresRefresh: false) }
            router.open(messageID: id.rawValue, cachedMessage: cached)
        case .notificationPreview(let id):
            let userInfo = DemoBossAPI().notificationPreviewUserInfo(for: id) ?? [:]
            router.open(messageID: id.rawValue, cachedMessage: PushMessageSnapshot.decode(from: userInfo))
        case .session(let id, let label):
            tab = Self.activityTab
            activitySection = .sessions
            activityPath = NavigationPath([SessionRoute(id: id, label: label)])
        case .resolved:
            tab = Self.activityTab
            activitySection = .messages
            activityPath = NavigationPath([ResolvedRoute()])
        case .panel(let id):
            router.open(panel: PushPanelRequest(panelID: id, requestID: "demo-request"))
        case .joinRequest(let id):
            router.openJoinRequest(id: id)
        }
    }
}
