// Settings root: five summary rows with native navigation to connection, devices and notifications.
// Exports: SettingsView bound to the ConnectionStore, rendered as a native Form.
// Dependencies: SwiftUI, HibossKit, Push/Preferences stores.

import HibossKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var connection: ConnectionStore
    /// Live stream state, so Status reflects the real connection — not just that
    /// credentials exist (a revoked token used to still read "Connected").
    let connectionState: ConnectionState
    @ObservedObject var prefs: PreferencesStore
    @ObservedObject var joinRequests: JoinRequestsModel
    /// Re-attaches the stream with the existing token (transient failures / a
    /// recovered server), without wiping credentials like Sign Out does.
    var onReconnect: () -> Void = {}
    var onDecisionAlertsChanged: (Bool) -> Void = { _ in }
    @StateObject private var push = PushStatusStore()
    @State private var confirmsSignOut = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section {
                connectionLink
                devicesLink
                notificationsLink
            }
            Section {
                NavigationLink {
                    SettingsAboutView()
                } label: {
                    Text("About")
                }
                .accessibilityIdentifier("settings-about")
            }

            Section {
                Button("Sign Out", role: .destructive) { confirmsSignOut = true }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("settings-sign-out")
                    // Signing out deletes this phone's token; returning needs another device or a Boss Token.
                    .confirmationDialog("Sign out of HiBoss?", isPresented: $confirmsSignOut,
                                        titleVisibility: .visible) {
                        Button("Sign Out", role: .destructive) { connection.signOut() }
                    } message: {
                        Text("This iPhone forgets its device token and signing key.")
                            + Text(" To sign in again, pair it from another device or enter a Boss Token.")
                    }
            }
        }
        .navigationTitle("Settings")
        .task {
            await push.refresh()
            if case .idle = prefs.state {
                if isDemoMode { prefs.loadDemo() } else { await prefs.load(api: connection.makeAPI()) }
                onDecisionAlertsChanged(prefs.decisionAlerts)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await push.refresh()
                if case .failed = prefs.state, !prefs.isDirty, !isDemoMode {
                    await prefs.load(api: connection.makeAPI())
                    onDecisionAlertsChanged(prefs.decisionAlerts)
                }
            }
        }
    }

    private var connectionLink: some View {
        NavigationLink {
            SettingsConnectionView(connection: connection, connectionState: connectionState,
                                   onReconnect: onReconnect)
        } label: {
            SettingsConnectionSummary(
                server: connection.config?.serverURL.host() ?? (isDemoMode
                    ? String(localized: "Sample server") : String(localized: "Sign in to connect")),
                status: connection.isConfigured || isDemoMode
                    ? connectionState.label : String(localized: "Not connected")
            )
        }
        .accessibilityIdentifier("settings-connection")
    }

    private var devicesLink: some View {
        NavigationLink {
            SettingsDevicesView(connection: connection, joinRequests: joinRequests)
        } label: {
            Text("Devices")
        }
        .badge(joinRequests.pendingCount)
        .accessibilityValue(Text("\(joinRequests.pendingCount) pending"))
        .accessibilityIdentifier("settings-devices")
    }

    private var notificationsLink: some View {
        NavigationLink {
            SettingsNotificationsView(store: prefs, push: push, api: connection.makeAPI(),
                                      onDecisionAlertsChanged: onDecisionAlertsChanged)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Notifications")
                Text(verbatim: prefs.isDirty ? String(localized: "Unsaved changes") : push.label)
                    .font(.subheadline).foregroundStyle(Theme.ink2)
                if prefs.hasLoaded, prefs.quietHours.enabled {
                    Text("Quiet hours \(prefs.quietHours.start)–\(prefs.quietHours.end)")
                        .font(.subheadline).foregroundStyle(Theme.ink2)
                }
            }
        }
        .accessibilityIdentifier("settings-notifications")
    }
}
