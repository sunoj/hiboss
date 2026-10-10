// General pane for this Mac's app-level startup and Dock visibility preferences.
// Exports: GeneralSettingsPane.
// Dependencies: AppKit, SwiftUI, AppSettings, and LaunchAtLoginController.

import AppKit
import SwiftUI

struct GeneralSettingsPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var launchAtLogin: LaunchAtLoginController

    var body: some View {
        Form {
            Section {
                // Never gated on status: SMAppService reports .notFound for a
                // bundle Launch Services has not caught up with, and greying the
                // toggle out then hides a switch that would have worked.
                Toggle(
                    L("Open at login"),
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )
            } header: {
                Text(L("Startup"))
            } footer: {
                Text(launchAtLogin.explanation)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(L("Show in Dock"), isOn: $settings.showsInDock)
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
    }
}
