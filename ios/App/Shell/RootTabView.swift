// App shell: the native tab bar with a navigation stack per section.
// Exports: RootTabView switching Inbox / Messages / Sessions / Settings.
// Dependencies: SwiftUI, the feature views.

import SwiftUI

struct RootTabView: View {
    @ObservedObject var inbox: InboxStore
    @ObservedObject var connection: ConnectionStore

    var body: some View {
        TabView {
            NavigationStack {
                InboxView(store: inbox)
            }
            .tabItem { Label("Inbox", systemImage: "tray.full") }
            .badge(inbox.pendingCount)

            NavigationStack {
                MessagesView(store: inbox)
            }
            .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right") }

            NavigationStack {
                SessionsView(store: inbox)
            }
            .tabItem { Label("Sessions", systemImage: "square.stack.3d.up") }

            NavigationStack {
                SettingsView(connection: connection)
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
