// About pane for app version, build, and project links.
// Exports: AboutSettingsPane.
// Dependencies: SwiftUI and Bundle metadata.

import SwiftUI

struct AboutSettingsPane: View {
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
        }
        .formStyle(.grouped)
    }

    private func bundleValue(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "Development"
    }
}
