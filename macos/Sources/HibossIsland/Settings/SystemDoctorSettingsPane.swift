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
                LabeledContent(L("Daemon stream")) {
                    Text(flow.connectionState.label)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent(L("Server reachability")) {
                    Text(settings.isConfigured ? L("Configured") : L("Not configured"))
                        .foregroundStyle(.secondary)
                }
                LabeledContent(L("Last error")) {
                    Text(lastError)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text(L("Health"))
            } footer: {
                Text(L("Read-only diagnostics for the local daemon stream and preference store."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var lastError: String {
        if case let .failed(message) = flow.connectionState { return message }
        if case let .failed(message) = preferencesStore.state { return message }
        return L("None")
    }
}
