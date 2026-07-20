// System diagnostics pane for read-only app and server health.
// Exports: SystemDoctorSettingsPane.
// Dependencies: SwiftUI, HibossKit flow and preference state, and AppSettings.

import HibossKit
import SwiftUI

struct SystemDoctorSettingsPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var flow: OptionFlowStore
    @ObservedObject var preferencesStore: BossPreferencesStore

    var body: some View {
        SettingsPaneBody(pane: .systemDoctor) {
            SettingsSection(title: "Health") {
                SettingsRow(title: "Daemon stream", caption: "SSE connection state.") {
                    diagnosticText(flow.connectionState.label)
                }
                SettingsRow(title: "Server reachability", caption: "Local connection settings validation.") {
                    diagnosticText(settings.isConfigured ? "Configured" : "Not configured")
                }
                LastSettingsRow(title: "Last error", caption: "Most recent stream or preference failure.") {
                    diagnosticText(lastError)
                }
            }
        }
    }

    private var lastError: String {
        if case let .failed(message) = flow.connectionState { return message }
        if case let .failed(message) = preferencesStore.state { return message }
        return "None"
    }

    private func diagnosticText(_ text: String) -> some View {
        Text(text)
            .font(Font.caption.monospaced())
            .tracking(0.7)
            .foregroundStyle(Color.secondary)
    }
}
