// About pane for app version, build, software updates, and project links.
// Exports: AboutSettingsPane.
// Dependencies: SwiftUI, HibossKit (UpdaterState), Bundle metadata.

import HibossKit
import SwiftUI

struct AboutSettingsPane: View {
    @ObservedObject var updater: UpdaterState

    var body: some View {
        Form {
            Section {
                LabeledContent("Version") {
                    Text(bundleValue("CFBundleShortVersionString"))
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Build") {
                    Text(bundleValue("CFBundleVersion"))
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Project") {
                    if let url = URL(string: "https://hiboss.ai") {
                        Link("hiboss.ai", destination: url)
                    } else {
                        Text("hiboss.ai")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("HiBoss Island")
            }

            Section {
                Toggle(
                    "Automatically check for updates",
                    isOn: Binding(
                        get: { updater.automaticChecks },
                        set: { updater.setAutomatic($0) }
                    )
                )
                .disabled(!updater.isConfigured)
                LabeledContent("Software update") {
                    Button("Check for Updates…") { updater.check() }
                        .disabled(!updater.canCheck)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text(
                    updater.isConfigured
                        ? "Updates are delivered via Sparkle and verified with an EdDSA signature before installing."
                        : "This build has no update feed configured, so it will not check for updates."
                )
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func bundleValue(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "Development"
    }
}
