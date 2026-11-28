// Settings › Connection: one state card (state, meaning, the server's reason and Reconnect), the server address, the signing key.
// Exports: SettingsConnectionView and SettingsConnectionSummary.
// Dependencies: SwiftUI, HibossKit ConnectionState, ConnectionStore, Theme.

import HibossKit
import SwiftUI

struct SettingsConnectionView: View {
    @ObservedObject var connection: ConnectionStore
    let connectionState: ConnectionState
    let onReconnect: () -> Void

    var body: some View {
        Form {
            stateSection
            serverSection
            SettingsSigningKeySection(signer: connection.messageSigner)
        }
        .formStyle(.grouped)
        .contentMargins(.horizontal, Space.m, for: .scrollContent)
        .navigationTitle("Connection")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var configured: Bool { connection.isConfigured || isDemoMode }

    /// One card: the state in words, what it means, and on failure the server's reason and one action.
    private var stateSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(spacing: Space.s) {
                    Circle().fill(stateColor).frame(width: Space.s, height: Space.s).accessibilityHidden(true)
                    Text(verbatim: configured ? connectionState.label : String(localized: "Not connected"))
                        .font(.title2.bold())
                        .accessibilityIdentifier("settings-connection-state")
                }
                if connectionState == .connecting {
                    SettingsWaitView(title: "Connecting to your server…", actionTitle: "Reconnect",
                                     action: onReconnect)
                } else {
                    Text(verbatim: SettingsConnectionSummary.guidance(connectionState, configured: configured))
                        .font(.subheadline).foregroundStyle(Theme.ink2)
                }
                if configured, let detail = connectionState.detail {
                    Label { Text(verbatim: detail) } icon: { Image(systemName: "exclamationmark.triangle") }
                        .font(.subheadline).foregroundStyle(Theme.warn)
                }
                if connection.isConfigured, case .failed = connectionState {
                    Button("Reconnect", action: onReconnect).hbButton(.primary)
                }
                if !configured {
                    Text("Sign in from the welcome screen to connect this phone.")
                        .font(.subheadline).foregroundStyle(Theme.ink2)
                }
            }
            .padding(.vertical, Space.xs)
        } footer: {
            if let notice = connection.clientExchangeNotice {
                Label { Text(verbatim: notice) } icon: { Image(systemName: "exclamationmark.triangle") }
            }
        }
    }

    private var serverSection: some View {
        Section("Server") {
            LabeledContent("Address") {
                Text(verbatim: connection.config?.serverURL.absoluteString
                     ?? (isDemoMode ? DemoDevices.serverURL.absoluteString : "—"))
                    .textSelection(.enabled)
            }
        }
    }

    private var stateColor: Color {
        guard configured else { return Theme.ink3 }
        switch connectionState {
        case .connected: return Theme.positive
        case .failed: return Theme.warn
        case .connecting, .disconnected: return Theme.ink3
        }
    }
}

struct SettingsConnectionSummary: View {
    let server: String
    let status: String

    var body: some View {
        LabeledContent {
            Text(verbatim: status)
        } label: {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("Connection")
                Text(verbatim: server).font(.caption).foregroundStyle(Theme.ink2)
            }
        }
    }

    static func guidance(_ state: ConnectionState, configured: Bool) -> String {
        guard configured else { return String(localized: "Sign in to connect this phone.") }
        switch state {
        case .failed: return String(localized: "Check your connection, then tap Reconnect.")
        case .connecting: return String(localized: "Connecting to your server…")
        case .disconnected: return String(localized: "Open HiBoss again to reconnect to your server.")
        case .connected: return String(localized: "This phone is connected to your server.")
        }
    }
}
