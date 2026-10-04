// Connection pane: live state, then Sign in with iPhone, Pair with Code, and a Boss Token.
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
    let onSignedIn: (ConnectionConfig) -> Void
    @State private var sheet: ConnectionSheet?

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
                signinWithPhoneButton
            } header: {
                Text(L("Sign in with iPhone"))
            } footer: {
                Text(L("Show a QR code here, approve it in HiBoss on a signed-in iPhone, then type the code the iPhone shows."))
                    .foregroundStyle(.secondary)
            }
            .disabled(isConnecting)

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
                    sheet = .devicePairing
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
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .devicePairing: DevicePairingSheet(settings: settings)
            case .signinWithPhone: SigninWithPhoneSheet(settings: settings, onSignedIn: onSignedIn)
            }
        }
    }

    @ViewBuilder
    private var signinWithPhoneButton: some View {
        let button = Button {
            sheet = .signinWithPhone
        } label: {
            Label(L("Sign in with iPhone…"), systemImage: "iphone")
        }
        if settings.isConfigured {
            button
        } else {
            button.buttonStyle(.borderedProminent)
        }
    }

    private var pairWithCodeButton: some View {
        Button {
            pairingLinks.request = PairingSheetRequest(link: "")
        } label: {
            Label(L("Pair with Code…"), systemImage: "link.badge.plus")
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

/// The sheets the Connection pane presents; one at a time.
enum ConnectionSheet: String, Identifiable {
    case devicePairing
    case signinWithPhone

    var id: String { rawValue }
}
