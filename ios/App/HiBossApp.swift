// App entry point: owns the connection + inbox stores and gates onboarding.
// Exports: HiBossApp (@main) and RootView.
// Dependencies: SwiftUI, HibossKit, feature stores and views.

import HibossKit
import SwiftUI

@main
struct HiBossApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var connection = ConnectionStore()
    @StateObject private var inbox = InboxStore()
    @StateObject private var preferences = PreferencesStore()
    @StateObject private var progress = ProgressFeedStore()

    var body: some Scene {
        WindowGroup {
            RootView(
                connection: connection,
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
    @State private var showsClientNotice = false
    @ObservedObject var connection: ConnectionStore
    @ObservedObject var inbox: InboxStore
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var progress: ProgressFeedStore

    var body: some View {
        Group {
            if isDemoMode && ProcessInfo.processInfo.environment["HIBOSS_DEMO_ACTIVITY"] == "1" {
                DemoActivityStateView()
            } else if connection.isRestoring && isDemoMode
                && ProcessInfo.processInfo.environment["HIBOSS_DEMO_RESTORE_DELAY_MS"]?.isEmpty == false {
                restoringView
            } else if ProcessInfo.processInfo.environment["HIBOSS_DEMO_ONBOARDING"] == "1" {
                ConnectView(connection: connection)
            } else if isDemoMode || connection.isConfigured {
                RootTabView(
                    inbox: inbox,
                    connection: connection,
                    preferences: preferences,
                    progress: progress
                )
            } else if connection.isRestoring {
                restoringView
            } else {
                ConnectView(connection: connection)
            }
        }
        .onChange(of: connection.config) { _, config in
            showsClientNotice = config != nil && connection.clientExchangeNotice != nil
            guard !isDemoMode else { return }
            preferences.connectionDidChange()
            if config != nil, let api = connection.makeAPI() {
                startConnectedServices(api)
            } else {
                inbox.stop()
                progress.stop()
            }
        }
        .alert("Device token notice", isPresented: $showsClientNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: connection.clientExchangeNotice ?? "")
        }
        .onAppear(perform: startInitialServices)
    }

    private func startInitialServices() {
        if isDemoMode {
            if !DemoDelay.isHeld("PREFERENCES") { preferences.loadDemo() }
            let flags = ProcessInfo.processInfo.environment
            if flags["HIBOSS_DEMO_PREFERENCES_DELAY_MS"]?.isEmpty == false
                || flags["HIBOSS_DEMO_PREFERENCES_SAVE_DELAY_MS"]?.isEmpty == false {
                Task { await preferences.load(api: DemoPreferencesAPI.make()) }
            }
            inbox.setDecisionAlertsEnabled(preferences.decisionAlerts)
            if ProcessInfo.processInfo.environment["HIBOSS_DEMO_CONNECTION"] != "disconnected" {
                let demo = DemoBossAPI()
                inbox.start(api: demo)
            }
            progress.start(api: DemoProgressAPI())
        } else if connection.isConfigured, let api = connection.makeAPI() {
            startConnectedServices(api)
        }
    }

    private var restoringView: some View {
        PendingStateView(
            title: String(localized: "Restoring your connection…"), showsPlaceholder: true,
            onRetry: { await connection.restore() }
        ).padding(16)
    }

    /// Start message loading immediately; preferences are not on the critical
    /// path for notification deep-links and may require a separate network round trip.
    private func startConnectedServices(_ api: HibossAPI) {
        inbox.setDecisionAlertsEnabled(preferences.decisionAlerts)
        inbox.start(api: api)
        progress.start(api: api)
        Task {
            await preferences.load(api: api)
            inbox.setDecisionAlertsEnabled(preferences.decisionAlerts)
            PushManager.shared.promptIfNeeded()
        }
    }
}
