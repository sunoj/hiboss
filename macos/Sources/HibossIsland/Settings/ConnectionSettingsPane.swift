// Connection pane for editing server URL and boss token.
// Exports: ConnectionSettingsPane.
// Dependencies: SwiftUI, AppSettings, OptionFlowStore, and DesignTokens.

import HibossKit
import SwiftUI

struct ConnectionSettingsPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var flow: OptionFlowStore
    let statusMessage: String
    let isConnecting: Bool
    let reconnect: () -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    Label {
                        Text(connectionTitle)
                    } icon: {
                        Image(systemName: statusSymbol)
                            .foregroundStyle(statusTint)
                    }
                }
                LabeledContent("Endpoint") {
                    Text(connectionDetail)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Button("Reconnect", action: reconnect)
                    .disabled(isConnecting)
            } header: {
                Text("Daemon")
            }

            Section {
                TextField("Server URL", text: $settings.serverAddress)
                    .font(.system(.body, design: .monospaced))
                SecureField("Boss Token", text: $settings.bossToken)
            } header: {
                Text("Credentials")
            } footer: {
                Text("Token is stored locally in Keychain.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var statusSymbol: String {
        flow.connectionState == .connected ? "circle.fill" : "circle"
    }

    private var statusTint: Color {
        flow.connectionState == .connected
            ? DesignTokens.live
            : Color(nsColor: .tertiaryLabelColor)
    }

    private var connectionTitle: String {
        switch flow.connectionState {
        case .connected: "Connected · daemon running"
        case .connecting: "Connecting · daemon pending"
        case .disconnected: "Disconnected · daemon idle"
        case .failed: "Disconnected · daemon error"
        }
    }

    private var connectionDetail: String {
        if !statusMessage.isEmpty { return statusMessage }
        guard case let .success(config) = settings.connectionConfig() else {
            return "not configured"
        }
        return config.serverURL.host ?? config.serverURL.absoluteString
    }
}
