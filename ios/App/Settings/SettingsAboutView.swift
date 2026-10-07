// Installed app identity in a native Settings detail Form.
// Exports: SettingsAboutView. Reads version and build from the app bundle.
// Dependencies: SwiftUI, Foundation Bundle.

import SwiftUI

struct SettingsAboutView: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("App", value: "HiBoss")
                LabeledContent("Version", value: Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                LabeledContent("Build", value: Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
