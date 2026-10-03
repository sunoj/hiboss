// Settings tab: connection, notifications, boss preferences, and sign-out.
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
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section {
                LabeledContent("Server", value: connection.config?.serverURL.host() ?? "—")
                LabeledContent("Status") {
                    if connection.isConfigured {
                        Text(verbatim: connectionState.label)
                    } else {
                        Text("Not connected").foregroundStyle(.secondary)
                    }
                }
                if connection.isConfigured, case .failed = connectionState {
                    Button("Reconnect", action: onReconnect)
                }
            } header: {
                Text("Connection")
            } footer: {
                if let notice = connection.clientExchangeNotice {
                    Label { Text(verbatim: notice) } icon: { Image(systemName: "exclamationmark.triangle") }
                }
                if let detail = connectionState.detail {
                    Text(verbatim: detail).foregroundStyle(.red)
                }
            }

            if let config = connection.config {
                Section {
                    NavigationLink {
                        PairDeviceView(config: config)
                    } label: {
                        Label("Pair another device", systemImage: "qrcode")
                    }
                } footer: {
                    Text("Show a one-time code that signs in another iPhone or Mac. No token leaves this phone.")
                }
                Section {
                    NavigationLink {
                        DeviceRequestsView(model: joinRequests)
                    } label: {
                        Label("Device Requests", systemImage: "desktopcomputer.and.arrow.down")
                    }
                    .badge(joinRequests.pendingCount)
                } footer: {
                    Text("Machines that run hiboss setup with an invite wait here until an admin approves them.")
                }
            }

            if let api = connection.makeAPI(), let config = connection.config {
                BossClientsSection(api: api, kind: .ios, deviceLabel: connection.deviceLabel) { token in
                    try connection.activateDeviceToken(token, replacing: config)
                }
                    .id(connection.config?.bossToken)
            }

            NotificationsSection(push: push)

            if prefs.state != .unavailable {
                RoutingSection(store: prefs)
                QuietHoursSection(store: prefs)
                PushTieringSection(store: prefs)
                Section {
                    Toggle("Private Notifications", isOn: Binding(
                        get: { prefs.privatePush },
                        set: { prefs.setPrivatePush($0) }
                    ))
                    Toggle("Alert on decisions", isOn: Binding(
                        get: { prefs.decisionAlerts },
                        set: {
                            prefs.setDecisionAlerts($0)
                            onDecisionAlertsChanged($0)
                        }
                    ))
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Keep message content off Apple's servers: pushes show only a generic alert, and the app fetches the body from your server when opened.")
                        Text("Requests that need a decision light up the Dynamic Island and lock screen even at normal priority. Turn off to let them follow normal priority tiering.")
                    }
                }
                preferencesStatus
            }

            if prefs.isDirty {
                Section {
                    Button {
                        Task { await prefs.save() }
                    } label: {
                        HStack {
                            if prefs.isSaving { ProgressView() }
                            Text(prefs.isSaving ? String(localized: "Saving…") : String(localized: "Save Changes"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(prefs.isSaving)
                }
            }

            Section {
                Button("Sign Out", role: .destructive) { connection.signOut() }
                    .frame(maxWidth: .infinity)
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

    @ViewBuilder
    private var preferencesStatus: some View {
        switch prefs.state {
        case .loading:
            Section { Label("Loading preferences…", systemImage: "arrow.clockwise").foregroundStyle(.secondary) }
        case let .failed(message):
            Section { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
        default:
            EmptyView()
        }
    }
}

private struct NotificationsSection: View {
    @ObservedObject var push: PushStatusStore
    @ObservedObject private var manager = PushManager.shared

    var body: some View {
        Section("Notifications") {
            LabeledContent("Push") {
                Text(verbatim: push.label).foregroundStyle(push.isEnabled ? .green : .secondary)
            }
            // OS authorization ≠ the server actually has a live device token; show
            // the registration result so "Enabled" can't hide a device that
            // receives nothing.
            if push.isEnabled {
                LabeledContent("Device") { deviceStatus }
            }
            if !push.isEnabled {
                Button(actionTitle) {
                    if push.mustOpenSystemSettings { push.openSystemSettings() } else { push.request() }
                }
            }
        }
    }

    @ViewBuilder
    private var deviceStatus: some View {
        switch manager.registration {
        case .idle:
            Text("Not registered").foregroundStyle(.secondary)
        case .registering:
            HStack(spacing: 6) { ProgressView(); Text("Registering…").foregroundStyle(.secondary) }
        case .registered:
            Label("Registered", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
        }
    }

    private var actionTitle: String {
        push.mustOpenSystemSettings ? String(localized: "Open Settings to Enable") : String(localized: "Enable Notifications")
    }
}
