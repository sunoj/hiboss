// Connection details and recovery, preserving the authenticated stream reconnect action.
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
            connectionSection
            guidanceSection
        }
        .navigationTitle("Connection")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { reconnectButton }
    }

    private var connectionSection: some View {
        Section {
            LabeledContent("Server") {
                Text(verbatim: connection.config?.serverURL.absoluteString
                     ?? (isDemoMode ? DemoDevices.serverURL.absoluteString : "—"))
                    .textSelection(.enabled)
            }
            LabeledContent("Status") {
                if connection.isConfigured || isDemoMode {
                    Text(verbatim: connectionState.label)
                } else {
                    Text("Not connected").foregroundStyle(Theme.ink2)
                }
            }
        } header: {
            Text("Connection")
        } footer: {
            if let notice = connection.clientExchangeNotice {
                Label { Text(verbatim: notice) } icon: { Image(systemName: "exclamationmark.triangle") }
            }
            if let detail = connectionState.detail {
                Text(verbatim: detail).foregroundStyle(Theme.negative)
            }
        }

    }

    private var guidanceSection: some View {
        Section {
            if connectionState == .connecting {
                SettingsWaitView(title: "Connecting to your server…", actionTitle: "Reconnect",
                                 action: onReconnect)
            } else {
                Text(verbatim: SettingsConnectionSummary.guidance(
                    connectionState, configured: connection.isConfigured || isDemoMode))
            }
            if !connection.isConfigured, !isDemoMode {
                Text("Sign in from the welcome screen to connect this phone.")
            }
        }
    }

    @ViewBuilder
    private var reconnectButton: some View {
        if connection.isConfigured, case .failed = connectionState {
            Button("Reconnect", action: onReconnect)
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.borderedProminent)
                .padding()
                .background(Theme.paper)
        }
    }

}

struct SettingsConnectionSummary: View {
    let server: String
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Connection")
            Text(verbatim: server).font(.subheadline).foregroundStyle(Theme.ink2)
            Text(verbatim: status).font(.subheadline).foregroundStyle(Theme.ink2)
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
