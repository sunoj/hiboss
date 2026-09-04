// App shell: native tabs, one message surface, and notification deep-links.
// Exports: RootTabView switching Home / Messages / Progress / Sessions / Settings.
// Dependencies: SwiftUI, HibossKit, the feature views, AppRouter, DemoLaunchRoute.

import HibossKit
import SwiftUI

struct RootTabView: View {
    @ObservedObject var home: HomeStore
    @ObservedObject var inbox: InboxStore
    @ObservedObject var connection: ConnectionStore
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var progress: ProgressFeedStore
    @ObservedObject private var router = AppRouter.shared
    @Environment(\.scenePhase) private var scenePhase

    /// Tab indices are referenced from playback gating and demo routing, so they are
    /// named rather than written as literals — renumbering silently broke video
    /// autoplay once, by leaving it pointed at whichever tab had inherited the index.
    private static let homeTab = 0
    private static let messagesTab = 1
    private static let progressTab = 3

    @State private var tab = ProcessInfo.processInfo.environment["HIBOSS_TAB"] == "progress"
        ? Self.progressTab
        : Self.homeTab
    @State private var homePath = NavigationPath()
    @State private var messagesPath = NavigationPath()

    private var sessionStreamAPI: (any SessionStreamServing)? {
        if isDemoMode { return DemoBossAPI() }
        return connection.makeAPI()
    }

    var body: some View {
        TabView(selection: $tab) {
            homeTabView
            messagesTabView
            progressTabView
            sessionsTabView
            settingsTabView
        }
        .task(id: router.pendingMessageID) { await openPendingMessage() }
        .onChange(of: scenePhase) { _, phase in
            // iOS drops the SSE while backgrounded; on return, reload history so
            // decisions that arrived (or resolved elsewhere) meanwhile show up.
            if phase == .active { inbox.refreshHistory() }
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
            HomeView(inbox: inbox, sessionAPI: sessionStreamAPI)
        }
        .tabItem { Label("Home", systemImage: "house") }
        .tag(Self.homeTab)
    }

    private var messagesTabView: some View {
        NavigationStack(path: $messagesPath) {
            MessagesView(store: inbox)
                .navigationTitle("Messages")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { ConnectionDot(state: inbox.connectionState) } }
                .navigationDestination(for: MessageID.self) { MessageDetailView(store: inbox, messageID: $0) }
                .navigationDestination(for: SessionRoute.self) { SessionMessagesView(route: $0, api: sessionStreamAPI) }
                .navigationDestination(for: ResolvedRoute.self) { _ in ResolvedDecisionsView(store: inbox) }
        }
        .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right") }
        .tag(Self.messagesTab)
    }

    private var progressTabView: some View {
        NavigationStack { ProgressFeedView(store: progress) }
            .tabItem { Label("Progress", systemImage: "calendar.day.timeline.leading") }
            .tag(Self.progressTab)
    }

    private var sessionsTabView: some View {
        NavigationStack {
            SessionsView(store: inbox)
                .navigationDestination(for: SessionRoute.self) { SessionMessagesView(route: $0, api: sessionStreamAPI) }
                .navigationDestination(for: MessageID.self) { MessageDetailView(store: inbox, messageID: $0) }
        }
        .tabItem { Label("Sessions", systemImage: "square.stack.3d.up") }
        .tag(4)
    }

    private var settingsTabView: some View {
        NavigationStack {
            SettingsView(
                connection: connection,
                connectionState: inbox.connectionState,
                prefs: preferences,
                onReconnect: reconnect,
                onDecisionAlertsChanged: { inbox.setDecisionAlertsEnabled($0) }
            )
        }
        .tabItem { Label("Settings", systemImage: "gearshape") }
        .tag(5)
    }

    private func reconnect() {
        guard let api = connection.makeAPI() else { return }
        inbox.start(api: api)
        progress.start(api: api)
        home.start(api: api)
        Task {
            await preferences.load(api: api)
            inbox.setDecisionAlertsEnabled(preferences.decisionAlerts)
        }
    }

    /// Opens a cached push snapshot immediately; ID-only private or oversized
    /// notifications briefly wait for the restored API before navigation.
    private func openPendingMessage() async {
        guard let route = router.pendingMessage else { return }
        if let detail = route.cachedDetail {
            inbox.cacheMessage(detail)
        } else {
            for _ in 0..<AppConstants.API.notificationReadinessChecks where !inbox.isReady {
                try? await Task.sleep(for: AppConstants.API.notificationReadinessDelay)
                if Task.isCancelled { return }
            }
        }
        await Task.yield()
        guard !Task.isCancelled else { return }
        tab = Self.messagesTab
        messagesPath = NavigationPath([route.messageID])
        router.finishOpening(route.messageID)
    }

    /// Screenshot / demo deep-links: open a message or a session thread.
    private func applyDemoRoute() {
        switch DemoLaunchRoute.resolve() {
        case .none:
            break
        case .open(let id):
            tab = Self.messagesTab
            messagesPath = NavigationPath([id])
        case .notification(let id):
            let detail = DemoBossAPI().messageDetail(for: id)
            router.open(messageID: id.rawValue, cachedDetail: detail)
        case .session(let id, let label):
            tab = Self.messagesTab
            messagesPath = NavigationPath([SessionRoute(id: id, label: label)])
        case .resolved:
            tab = Self.messagesTab
            messagesPath = NavigationPath([ResolvedRoute()])
        }
    }
}
