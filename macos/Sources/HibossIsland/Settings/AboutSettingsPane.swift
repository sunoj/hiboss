// About pane for app version, build, software updates, and project links.
// Exports: AboutSettingsPane.
// Dependencies: SwiftUI, HibossKit (UpdaterState), Bundle metadata.

import HibossKit
import SwiftUI

struct AboutSettingsPane: View {
    static let projectURL = URL(string: "https://hiboss.org")
    @ObservedObject var updater: UpdaterState

    var body: some View {
        Form {
            Section {
                LabeledContent(L("Version")) {
                    Text(bundleValue("CFBundleShortVersionString"))
                        .foregroundStyle(.secondary)
                }
                LabeledContent(L("Build")) {
                    Text(bundleValue("CFBundleVersion"))
                        .foregroundStyle(.secondary)
                }
                LabeledContent(L("Project")) {
                    if let url = Self.projectURL {
                        Link(destination: url) { Text(verbatim: url.host() ?? "") }
                    }
                }
            } header: {
                Text(L("HiBoss Island"))
            }

            Section {
                Toggle(
                    L("Automatically check for updates"),
                    isOn: Binding(
                        get: { updater.automaticChecks },
                        set: { updater.setAutomatic($0) }
                    )
                )
                .disabled(!updater.isConfigured)
                LabeledContent(L("Software update")) {
                    Button(L("Check for Updates…")) { updater.check() }
                        .disabled(!updater.canCheck)
                }
            } header: {
                Text(L("Updates"))
            } footer: {
                Text(
                    updater.isConfigured
                        ? L("Updates are delivered via Sparkle and verified with an EdDSA signature before installing.")
                        : L("This build has no update feed configured, so it will not check for updates.")
                )
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func bundleValue(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? L("Development")
    }
}
