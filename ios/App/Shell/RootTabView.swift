// App shell: native tabs, a navigation stack per section, and notification deep-links.
// Exports: RootTabView switching Inbox / Progress / Sessions / Settings.
// Dependencies: SwiftUI, HibossKit, the feature views, AppRouter.

import HibossKit
import SwiftUI

struct RootTabView: View {
    @ObservedObject var inbox: InboxStore
    @ObservedObject var connection: ConnectionStore
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var progress: ProgressFeedStore
    @ObservedObject private var router = AppRouter.shared
    @Environment(\.scenePhase) private var scenePhase

    /// Tab indices are referenced from playback gating and demo routing, so they are
    /// named rather than written as literals — renumbering silently broke video
    /// autoplay once, by leaving it pointed at whichever tab had inherited the index.
    private static let progressTab = 2

    @State private var tab = ProcessInfo.processInfo.environment["HIBOSS_TAB"] == "progress" ? Self.progressTab : 0
    @State private var inboxPath = NavigationPath()

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $inboxPath) {
                InboxView(store: inbox)
                    .navigationTitle("Inbox")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { ConnectionDot(state: inbox.connectionState) } }
                    .navigationDestination(for: MessageID.self) { MessageDetailView(store: inbox, messageID: $0) }
                    .navigationDestination(for: SessionRoute.self) { SessionMessagesView(store: inbox, route: $0) }
                    .navigationDestination(for: ResolvedRoute.self) { _ in ResolvedDecisionsView(store: inbox) }
            }
            .tabItem { Label("Inbox", systemImage: "tray.full") }
            .badge(inbox.pendingCount)
            .tag(0)

            NavigationStack {
                MessagesView(store: inbox)
                    .navigationTitle("Messages")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { ConnectionDot(state: inbox.connectionState) } }
                    .navigationDestination(for: MessageID.self) { MessageDetailView(store: inbox, messageID: $0) }
                    .navigationDestination(for: SessionRoute.self) { SessionMessagesView(store: inbox, route: $0) }
            }
            .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right") }
            .tag(1)

            NavigationStack {
                ProgressFeedView(store: progress)
            }
            .tabItem { Label("Progress", systemImage: "calendar.day.timeline.leading") }
            .tag(2)

            NavigationStack {
                SessionsView(store: inbox)
                    .navigationDestination(for: SessionRoute.self) { SessionMessagesView(store: inbox, route: $0) }
                    .navigationDestination(for: MessageID.self) { MessageDetailView(store: inbox, messageID: $0) }
            }
            .tabItem { Label("Sessions", systemImage: "square.stack.3d.up") }
            .tag(3)

            NavigationStack {
                SettingsView(
                    connection: connection,
                    connectionState: inbox.connectionState,
                    prefs: preferences,
                    onReconnect: {
                        if let api = connection.makeAPI() {
                            Task {
                                await preferences.load(api: api)
                                inbox.setDecisionAlertsEnabled(preferences.decisionAlerts)
                                inbox.start(api: api)
                                progress.start(api: api)
                            }
                        }
                    },
                    onDecisionAlertsChanged: { inbox.setDecisionAlertsEnabled($0) }
                )
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(4)
        }
        .onReceive(router.$pendingMessageID.compactMap { $0 }) { messageID in
            // Clear first to avoid re-entrancy, then build the stack in a single
            // atomic assignment: a reset-then-append pair in one update races
            // SwiftUI's pop-to-root and can leave the previously-open detail on
            // screen. NavigationPath([messageID]) lands exactly [messageID].
            // Decision notifications belong on Inbox, not the Messages firehose.
            router.pendingMessageID = nil
            tab = 0
            inboxPath = NavigationPath([messageID])
        }
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

    /// Screenshot / demo deep-links: open a message or a session thread.
    private func applyDemoRoute() {
        let env = ProcessInfo.processInfo.environment
        if let id = env["HIBOSS_DEMO_OPEN"], !id.isEmpty {
            tab = 0
            inboxPath = NavigationPath([MessageID(rawValue: id)])
            return
        }
        if env["HIBOSS_DEMO_SESSION"] == "1" {
            inboxPath = NavigationPath([SessionRoute(id: "sess-deploy", label: "prod-release")])
            return
        }
        if env["HIBOSS_DEMO_RESOLVED"] == "1" {
            tab = 0
            inboxPath = NavigationPath([ResolvedRoute()])
        }
    }
}
