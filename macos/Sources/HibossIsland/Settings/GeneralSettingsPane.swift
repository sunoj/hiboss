// General pane for this Mac's app-level behaviour (currently login startup).
// Exports: GeneralSettingsPane.
// Dependencies: AppKit, SwiftUI, and LaunchAtLoginController.

import AppKit
import SwiftUI

struct GeneralSettingsPane: View {
    @ObservedObject var launchAtLogin: LaunchAtLoginController

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Open at login",
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )
                .disabled(!launchAtLogin.isAvailable)
            } header: {
                Text("Startup")
            } footer: {
                Text(launchAtLogin.explanation)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
    }
}
