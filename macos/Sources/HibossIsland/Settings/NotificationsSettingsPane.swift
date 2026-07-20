// Notification pane for local presentation and interruption settings.
// Exports: NotificationsSettingsPane.
// Dependencies: SwiftUI, AppSettings, BossPreferencesStore, and preference logic.

import HibossKit
import SwiftUI

struct NotificationsSettingsPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var preferencesStore: BossPreferencesStore

    var body: some View {
        Form {
            Section {
                Picker("Option display", selection: $settings.optionDisplayMode) {
                    ForEach(OptionDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Toggle("Critical bypasses Do Not Disturb", isOn: criticalBypassBinding)
                Toggle("Show menu bar icon", isOn: $settings.showsStatusItem)
            } header: {
                Text("Delivery")
            } footer: {
                Text("Critical questions can still alert; the menu bar icon keeps HiBoss visible.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var criticalBypassBinding: Binding<Bool> {
        Binding {
            SettingsPreferencesLogic.quietHours(from: preferencesStore.preferences).criticalBypass
        } set: { value in
            var quietHours = SettingsPreferencesLogic.quietHours(from: preferencesStore.preferences)
            quietHours = QuietHours(
                enabled: quietHours.enabled,
                start: quietHours.start,
                end: quietHours.end,
                timezone: quietHours.timezone,
                days: quietHours.days,
                criticalBypass: value
            )
            preferencesStore.preferences = SettingsPreferencesLogic.preferences(
                preferencesStore.preferences,
                byUpdating: quietHours
            )
        }
    }
}
