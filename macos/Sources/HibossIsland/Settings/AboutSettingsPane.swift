// About pane for app version, build, and project links.
// Exports: AboutSettingsPane.
// Dependencies: SwiftUI and Bundle metadata.

import SwiftUI

struct AboutSettingsPane: View {
    var body: some View {
        SettingsPaneBody(pane: .about) {
            SettingsSection(title: "HiBoss Island") {
                SettingsRow(title: "Version", caption: "Marketing version from the app bundle.") {
                    valueText(bundleValue("CFBundleShortVersionString"))
                }
                SettingsRow(title: "Build", caption: "Build number from the app bundle.") {
                    valueText(bundleValue("CFBundleVersion"))
                }
                LastSettingsRow(title: "Project", caption: "Open the HiBoss project site.") {
                    Link("hiboss.ai", destination: URL(string: "https://hiboss.ai") ?? URL(fileURLWithPath: "/"))
                }
            }
        }
    }

    private func bundleValue(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "Development"
    }

    private func valueText(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Fonts.monoLabel)
            .tracking(0.7)
            .foregroundStyle(DesignTokens.Colors.ink3)
    }
}
