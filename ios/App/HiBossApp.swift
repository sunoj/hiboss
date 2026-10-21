// App entry point: owns connection, inbox and local session read state, and gates onboarding.
// Exports: HiBossApp (@main), AppSessionView and RootView.
// Dependencies: SwiftUI, HibossKit, feature stores and views.

import HibossKit
import SwiftUI

@main
struct HiBossApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var demo = DemoSession.shared

    var body: some Scene {
        WindowGroup {
            AppSessionView().id(demo.generation)
        }
    }
}

/// One signed-in, signed-out or demo session; rebuilt from scratch when a demo starts or ends.
struct AppSessionView: View {
    @StateObject private var connection = ConnectionStore()
    @StateObject private var inbox = InboxStore()
    @StateObject private var preferences = PreferencesStore()
    @StateObject private var progress = ProgressFeedStore()

    var body: some View {
        RootView(
            connection: connection,
            inbox: inbox,
            preferences: preferences,
            progress: progress
        )
            .task { await connection.restore() }
            .preferredColorScheme(isLaunchDemoMode ? DemoAppearance.colorScheme : nil)
            .onOpenURL { url in
                PairingLinkInbox.shared.receive(url)
                if connection.isConfigured { PairingLinkInbox.shared.discard() }
            }
    }
}

struct RootView: View {
    @State private var showsClientNotice = false
    @ObservedObject private var authorization = AccountAuthorization.shared
    @ObservedObject private var demo = DemoSession.shared
    @State private var generation = DemoSession.shared.generation
    @StateObject private var connectedPanels = ConnectedPanelsStore()
    @StateObject private var reads = SessionReadStore(
        defaults: isLaunchDemoMode ? UserDefaults(suiteName: "hiboss.demo.reads.\(UUID())")!
            : isDemoMode ? DemoSession.sessionReadDefaults() : .standard
    )
    @ObservedObject var connection: ConnectionStore
    @ObservedObject var inbox: InboxStore
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var progress: ProgressFeedStore

    var body: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.environment["HIBOSS_DEMO_SHARE"]?.isEmpty == false {
                DemoShareHost()
            } else {
                connectedRoot
            }
            #else
            connectedRoot
            #endif
        }
        .onChange(of: connection.config) { _, config in
            activateReads()
            if config != nil { PairingLinkInbox.shared.discard() }
            showsClientNotice = config != nil && connection.clientExchangeNotice != nil
            guard !isDemoMode else { return }
            preferences.connectionDidChange()
            if config != nil, let api = connection.makeAPI() {
                startConnectedServices(api)
            } else {
                inbox.stop()
                progress.stop()
                connectedPanels.stop()
            }
        }
        .alert("Device token notice", isPresented: $showsClientNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: connection.clientExchangeNotice ?? "")
        }
        .onAppear(perform: startInitialServices)
        .environmentObject(reads)
        .environment(\.unreadSessionIDs, reads.unreadSessionIDs(messages: inbox.history))
        .environment(\.needsYouSessionIDs,
                     Set(inbox.todaySnapshot(now: .now).sessionDirectory.needsYou.map(\.id)))
        .environment(\.agentAvatars, inbox.agentAvatars)
    }

    private var connectedRoot: some View {
        Group {
            if generation != demo.generation {
                // The session a demo enter or exit replaced renders nothing until it is torn
                // down, so its ConnectView cannot take a held pairing link.
                Color.clear
            } else if isDemoMode && ProcessInfo.processInfo.environment["HIBOSS_DEMO_ACTIVITY"] == "1" {
                DemoActivityStateView()
            } else if connection.isRestoring && isDemoMode
                && ProcessInfo.processInfo.environment["HIBOSS_DEMO_RESTORE_DELAY_MS"]?.isEmpty == false {
                restoringView
            } else if isDemoMode && ProcessInfo.processInfo.environment["HIBOSS_DEMO_ONBOARDING"] == "1" {
                ConnectView(connection: connection)
            } else if isDemoMode || connection.isConfigured {
                RootTabView(
                    inbox: inbox,
                    connection: connection,
                    preferences: preferences,
                    progress: progress,
                    panels: connectedPanels.model
                )
                .modifier(ProjectInventoryModifier(api: inbox.api as? any SessionsServing,
                                                   refreshRequested: inbox.isRefreshing))
                .id("\(BoxStore.connectionIdentity(connection.config))/\(authorization.generation)")
                .safeAreaInset(edge: .top, spacing: 0) {
                    if demo.isActive { DemoExitBar(onExit: exitDemo) }
                }
                .environment(\.exitDemo, demo.isActive ? exitDemo : nil)
            } else if connection.isRestoring {
                restoringView
            } else {
                ConnectView(connection: connection)
            }
        }
    }

    /// Stops every demo service before the session removes what the demo left behind.
    private func exitDemo() {
        inbox.stop()
        progress.stop()
        connectedPanels.stop()
        Task { await demo.exit() }
    }

    private func startInitialServices() {
        activateReads()
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
                connectedPanels.start(api: DemoPanelServices.make())
            }
            progress.start(api: DemoProgressAPI())
        } else if connection.isConfigured, let api = connection.makeAPI() {
            startConnectedServices(api)
        }
    }

    private func activateReads() {
        let config = isDemoMode
            ? ConnectionConfig(serverURL: URL(string: "https://demo.hiboss.invalid")!, bossToken: "demo")
            : connection.config
        let baseline = isDemoMode && ProcessInfo.processInfo.environment["HIBOSS_DEMO_SESSION_READS"] == "1"
            ? DemoSessionReads.baseline : Date.now
        reads.activate(config.map(SessionReadAccount.init(config:)), now: baseline)
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
        connectedPanels.start(config: connection.config)
        progress.start(api: api)
        Task {
            await preferences.load(api: api)
            inbox.setDecisionAlertsEnabled(preferences.decisionAlerts)
            PushManager.shared.promptIfNeeded()
        }
    }
}
