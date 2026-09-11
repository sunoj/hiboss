// Notification pane for local presentation and interruption settings.
// Exports: NotificationsSettingsPane.
// Dependencies: SwiftUI, AppSettings, BossPreferencesStore, and preference logic.

import HibossKit
import SwiftUI

struct NotificationsSettingsPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var preferencesStore: BossPreferencesStore
    @ObservedObject var notifications: MessageNotificationStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section {
                Toggle(L("Notify about messages"), isOn: Binding(
                    get: { notifications.isEnabled }, set: { notifications.setEnabled($0) }
                ))
                LabeledContent(L("Authorization"), value: notifications.authorization.label)
                if notifications.authorization == .denied {
                    Button(L("Open Notification Settings")) {
                        SystemMessageNotificationCenter.openSettings()
                    }
                }
                if let error = notifications.errorMessage {
                    Text(error).foregroundStyle(.secondary)
                }
            } footer: {
                Text(L("Message notifications do not apply quiet hours or priority filtering."))
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker(L("Option display"), selection: $settings.optionDisplayMode) {
                    ForEach(OptionDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Toggle(L("Critical bypasses Do Not Disturb"), isOn: criticalBypassBinding)
                Toggle(L("Show menu bar icon"), isOn: $settings.showsStatusItem)
            } header: {
                Text(L("Delivery"))
            } footer: {
                Text(L("Critical questions can still alert; the menu bar icon keeps HiBoss visible."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await notifications.refreshAuthorization() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await notifications.refreshAuthorization() } }
        }
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
