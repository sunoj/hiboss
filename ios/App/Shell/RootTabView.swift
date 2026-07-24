// App shell: native tabs, a navigation stack per section, and notification deep-links.
// Exports: RootTabView switching Inbox / Messages / Sessions / Settings.
// Dependencies: SwiftUI, HibossKit, the feature views, AppRouter.

import HibossKit
import SwiftUI

struct RootTabView: View {
    @ObservedObject var inbox: InboxStore
    @ObservedObject var connection: ConnectionStore
    @ObservedObject private var router = AppRouter.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab = 0
    @State private var inboxPath = NavigationPath()

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $inboxPath) {
                InboxView(store: inbox)
                    .navigationDestination(for: MessageID.self) { MessageDetailView(store: inbox, messageID: $0) }
                    .navigationDestination(for: SessionRoute.self) { SessionMessagesView(store: inbox, route: $0) }
            }
            .tabItem { Label("Inbox", systemImage: "tray.full") }
            .badge(inbox.pendingCount)
            .tag(0)

            NavigationStack {
                MessagesView(store: inbox)
                    .navigationDestination(for: MessageID.self) { MessageDetailView(store: inbox, messageID: $0) }
                    .navigationDestination(for: SessionRoute.self) { SessionMessagesView(store: inbox, route: $0) }
            }
            .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right") }
            .tag(1)

            NavigationStack {
                SessionsView(store: inbox)
                    .navigationDestination(for: SessionRoute.self) { SessionMessagesView(store: inbox, route: $0) }
                    .navigationDestination(for: MessageID.self) { MessageDetailView(store: inbox, messageID: $0) }
            }
            .tabItem { Label("Sessions", systemImage: "square.stack.3d.up") }
            .tag(2)

            NavigationStack {
                SettingsView(
                    connection: connection,
                    connectionState: inbox.connectionState,
                    onReconnect: { if let api = connection.makeAPI() { inbox.start(api: api) } }
                )
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(3)
        }
        .onReceive(router.$pendingMessageID.compactMap { $0 }) { messageID in
            // Clear first to avoid re-entrancy, then build the stack in a single
            // atomic assignment: a reset-then-append pair in one update races
            // SwiftUI's pop-to-root and can leave the previously-open detail on
            // screen. NavigationPath([messageID]) lands exactly [messageID].
            router.pendingMessageID = nil
            tab = 0
            inboxPath = NavigationPath([messageID])
        }
        .onChange(of: scenePhase) { _, phase in
            // iOS drops the SSE while backgrounded; on return, reload history so
            // decisions that arrived (or resolved elsewhere) meanwhile show up.
            if phase == .active { inbox.refreshHistory() }
        }
    }
}
