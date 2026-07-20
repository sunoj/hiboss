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
        SettingsPaneBody(pane: .connection) {
            statusCard
            SettingsSection(title: "Credentials") {
                SettingsRow(title: "Server URL", caption: "HTTP endpoint for the HiBoss daemon.") {
                    TextField("https://hiboss.local", text: $settings.serverAddress)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13).monospaced())
                        .frame(width: 280)
                }
                LastSettingsRow(title: "Boss Token", caption: "Stored locally in Keychain.") {
                    SecureField("Token", text: $settings.bossToken)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                }
            }
        }
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            PulsingStatusDot(isActive: flow.connectionState == .connected)
            VStack(alignment: .leading, spacing: 4) {
                Text(connectionTitle)
                    .font(Font.headline)
                    .foregroundStyle(Color.primary)
                HStack(spacing: 8) {
                    Text(connectionDetail)
                        .font(Font.caption.monospaced())
                        .tracking(0.7)
                    Text("SSE")
                        .font(Font.caption.monospaced())
                        .tracking(0.7)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .overlay {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.tile)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        }
                }
                .foregroundStyle(Color.secondary)
            }
            Spacer()
            Button("Reconnect", action: reconnect)
                .disabled(isConnecting)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.notice))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.notice)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
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
            return "not configured · --ms"
        }
        return "\(config.serverURL.host ?? config.serverURL.absoluteString) · --ms"
    }
}
