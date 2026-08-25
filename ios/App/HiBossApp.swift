// App entry point: owns the connection + inbox stores and gates onboarding.
// Exports: HiBossApp (@main) and RootView.
// Dependencies: SwiftUI, HibossKit, feature stores and views.

import SwiftUI

@main
struct HiBossApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var connection = ConnectionStore()
    @StateObject private var home = HomeStore()
    @StateObject private var inbox = InboxStore()
    @StateObject private var preferences = PreferencesStore()
    @StateObject private var progress = ProgressFeedStore()

    var body: some Scene {
        WindowGroup {
            RootView(
                connection: connection,
                home: home,
                inbox: inbox,
                preferences: preferences,
                progress: progress
            )
                .task { await connection.restore() }
                .preferredColorScheme(nil)
        }
    }
}

struct RootView: View {
    @ObservedObject var connection: ConnectionStore
    @ObservedObject var home: HomeStore
    @ObservedObject var inbox: InboxStore
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var progress: ProgressFeedStore

    var body: some View {
        Group {
            if isDemoMode || connection.isConfigured {
                RootTabView(
                    home: home,
                    inbox: inbox,
                    connection: connection,
                    preferences: preferences,
                    progress: progress
                )
            } else if connection.isRestoring {
                ProgressView().controlSize(.large)
            } else {
                ConnectView(connection: connection)
            }
        }
        .onChange(of: connection.config) { _, config in
            guard !isDemoMode else { return }
            if config != nil, let api = connection.makeAPI() {
                Task {
                    await preferences.load(api: api)
                    inbox.setDecisionAlertsEnabled(preferences.decisionAlerts)
                    inbox.start(api: api)
                    progress.start(api: api)
                    home.start(api: api)
                    PushManager.shared.promptIfNeeded()
                }
            } else {
                inbox.stop()
                progress.stop()
                home.stop()
            }
        }
        .onAppear {
            if isDemoMode {
                preferences.loadDemo()
                inbox.setDecisionAlertsEnabled(preferences.decisionAlerts)
                if ProcessInfo.processInfo.environment["HIBOSS_DEMO_CONNECTION"] != "disconnected" {
                    let demo = DemoBossAPI()
                    inbox.start(api: demo)
                    home.start(api: demo)
                }
                progress.start(api: DemoProgressAPI())
            } else if connection.isConfigured, let api = connection.makeAPI() {
                Task {
                    await preferences.load(api: api)
                    inbox.setDecisionAlertsEnabled(preferences.decisionAlerts)
                    inbox.start(api: api)
                    progress.start(api: api)
                    home.start(api: api)
                    PushManager.shared.promptIfNeeded()
                }
            }
        }
    }
}
