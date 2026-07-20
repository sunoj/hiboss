// Notification pane for local presentation and interruption settings.
// Exports: NotificationsSettingsPane.
// Dependencies: SwiftUI, AppSettings, BossPreferencesStore, and preference logic.

import HibossKit
import SwiftUI

struct NotificationsSettingsPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var preferencesStore: BossPreferencesStore

    var body: some View {
        SettingsPaneBody(pane: .notifications) {
            SettingsSection(title: "Delivery") {
                SettingsRow(title: "Option display", caption: "Choose how incoming questions open.") {
                    optionDisplayControl
                        .frame(width: 260)
                }
                SettingsRow(title: "Critical bypasses Do Not Disturb", caption: "Critical questions can still alert.") {
                    Toggle("", isOn: criticalBypassBinding)
                        .labelsHidden()
                }
                LastSettingsRow(title: "Show menu bar icon", caption: "Keep HiBoss visible in the macOS menu bar.") {
                    Toggle("", isOn: $settings.showsStatusItem)
                        .labelsHidden()
                }
            }
        }
    }

    private var optionDisplayControl: some View {
        Picker("", selection: $settings.optionDisplayMode) {
            ForEach(OptionDisplayMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
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
