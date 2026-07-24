// App entry point: owns the connection + inbox stores and gates onboarding.
// Exports: HiBossApp (@main) and RootView.
// Dependencies: SwiftUI, HibossKit, feature stores and views.

import SwiftUI

@main
struct HiBossApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var connection = ConnectionStore()
    @StateObject private var inbox = InboxStore()

    var body: some Scene {
        WindowGroup {
            RootView(connection: connection, inbox: inbox)
                .task { await connection.restore() }
                .preferredColorScheme(nil)
        }
    }
}

struct RootView: View {
    @ObservedObject var connection: ConnectionStore
    @ObservedObject var inbox: InboxStore

    var body: some View {
        Group {
            if isDemoMode || connection.isConfigured {
                RootTabView(inbox: inbox, connection: connection)
            } else if connection.isRestoring {
                ProgressView().controlSize(.large)
            } else {
                ConnectView(connection: connection)
            }
        }
        .onChange(of: connection.config) { _, config in
            guard !isDemoMode else { return }
            if config != nil, let api = connection.makeAPI() {
                inbox.start(api: api)
                PushManager.shared.promptIfNeeded()
            } else {
                inbox.stop()
            }
        }
        .onAppear {
            if isDemoMode {
                inbox.start(api: DemoBossAPI())
            } else if connection.isConfigured, let api = connection.makeAPI() {
                inbox.start(api: api)
                PushManager.shared.promptIfNeeded()
            }
        }
    }
}
