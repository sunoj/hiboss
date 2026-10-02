// Connection pane: live connection state with its failure reason, endpoint, and credentials.
// Exports: ConnectionSettingsPane.
// Dependencies: SwiftUI, AppSettings, OptionFlowStore, and DesignTokens.

import HibossKit
import SwiftUI

struct ConnectionSettingsPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var flow: OptionFlowStore
    let isConnecting: Bool
    let reconnect: () -> Void
    @State private var isPairingPresented = false

    var body: some View {
        Form {
            Section {
                LabeledContent(L("Status")) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Label {
                            Text(status.title)
                        } icon: {
                            Image(systemName: status.isLive ? "circle.fill" : "circle")
                                .foregroundStyle(status.isLive ? DesignTokens.live : Color(nsColor: .tertiaryLabelColor))
                        }
                        if let detail = status.detail {
                            Text(detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                        }
                    }
                }
                LabeledContent(L("Endpoint")) {
                    Text(endpoint)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Button(L("Reconnect"), action: reconnect)
                    .disabled(isConnecting)
            } header: {
                Text(L("Connection"))
            }

            Section {
                TextField(L("Server URL"), text: $settings.serverAddress)
                    .font(.system(.body, design: .monospaced))
                SecureField(L("Boss Token"), text: $settings.bossToken)
                TextField(L("Device label"), text: $settings.deviceLabel)
            } header: {
                Text(L("Credentials"))
            } footer: {
                Text(L("Token is stored locally in Keychain."))
                    .foregroundStyle(.secondary)
                if let notice = settings.clientExchangeNotice {
                    Label(notice, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(isConnecting)

            Section {
                Button {
                    isPairingPresented = true
                } label: {
                    Label(L("Pair a new device…"), systemImage: "qrcode")
                }
                .disabled(!settings.isConfigured)
            } header: {
                Text(L("Device pairing"))
            } footer: {
                Text(L("Show a one-time QR code that includes this server and enrolls a phone without typing a token."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isPairingPresented) {
            DevicePairingSheet(settings: settings)
        }
    }

    private var status: SettingsConnectionStatus {
        SettingsConnectionStatus(flow.connectionState)
    }

    private var endpoint: String {
        guard case let .success(config) = settings.connectionConfig() else {
            return L("not configured")
        }
        return config.serverURL.host ?? config.serverURL.absoluteString
    }
}
