// Connection pane: live state, then Pair with Code first and a Boss Token second.
// Exports: ConnectionSettingsPane.
// Dependencies: SwiftUI, AppSettings, OptionFlowStore, PairingLinkRouter, and DesignTokens.

import HibossKit
import SwiftUI

struct ConnectionSettingsPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var flow: OptionFlowStore
    let pairingLinks: PairingLinkRouter
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
                pairWithCodeButton
            } header: {
                Text(L("Pair with code"))
            } footer: {
                Text(L("Paste a hiboss://pair link from a signed-in device, or type its server and one-time code."))
                    .foregroundStyle(.secondary)
            }
            .disabled(isConnecting)

            Section {
                TextField(L("Server URL"), text: $settings.serverAddress)
                    .font(.system(.body, design: .monospaced))
                SecureField(L("Boss Token"), text: $settings.bossToken)
                TextField(L("Device label"), text: $settings.deviceLabel)
            } header: {
                Text(L("Use a Boss Token"))
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

    @ViewBuilder
    private var pairWithCodeButton: some View {
        let button = Button {
            pairingLinks.request = PairingSheetRequest(link: "")
        } label: {
            Label(L("Pair with Code…"), systemImage: "link.badge.plus")
        }
        if settings.isConfigured {
            button
        } else {
            button.buttonStyle(.borderedProminent)
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
