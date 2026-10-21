// About pane for app version, build, software updates, project links, and acknowledgements.
// Exports: AboutSettingsPane.
// Dependencies: SwiftUI, HibossKit (UpdaterState), Bundle metadata, Acknowledgements.

import HibossKit
import SwiftUI

struct AboutSettingsPane: View {
    static let projectURL = URL(string: "https://hiboss.org")
    @ObservedObject var updater: UpdaterState
    @State var isLicenseExpanded = false

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

            Section {
                DisclosureGroup(isExpanded: $isLicenseExpanded) {
                    ScrollView {
                        Text(verbatim: Acknowledgements.sparkleLicense)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 220)
                    .accessibilityIdentifier("about-sparkle-license")
                } label: {
                    if let url = Acknowledgements.sparkleURL {
                        Link(destination: url) { Text(verbatim: Acknowledgements.sparkleName) }
                    }
                }
            } header: {
                Text(L("Acknowledgements"))
            } footer: {
                Text(L("Software updates use Sparkle, which is distributed under this license."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func bundleValue(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? L("Development")
    }
}
