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
        Form {
            Section {
                LabeledContent("Daemon stream") {
                    Text(flow.connectionState.label)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("Server reachability") {
                    Text(settings.isConfigured ? "Configured" : "Not configured")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Last error") {
                    Text(lastError)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Health")
            } footer: {
                Text("Read-only diagnostics for the local daemon stream and preference store.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var lastError: String {
        if case let .failed(message) = flow.connectionState { return message }
        if case let .failed(message) = preferencesStore.state { return message }
        return "None"
    }
}
