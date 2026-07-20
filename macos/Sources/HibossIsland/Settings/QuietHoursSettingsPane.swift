// Quiet Hours pane for server-backed notification silencing preferences.
// Exports: QuietHoursSettingsPane.
// Dependencies: SwiftUI, HibossKit QuietHours, and settings preference logic.

import HibossKit
import SwiftUI

struct QuietHoursSettingsPane: View {
    @ObservedObject var preferencesStore: BossPreferencesStore

    var body: some View {
        SettingsPaneBody(pane: .quietHours) {
            SettingsNotAppliedNotice()
            SettingsSection(title: "Schedule") {
                SettingsRow(title: "Quiet Hours", caption: "Silence normal & low; critical still alerts.") {
                    Toggle("", isOn: enabledBinding)
                        .labelsHidden()
                }
                SettingsRow(title: "Time range", caption: "Use 24-hour HH:mm local times.") {
                    HStack(spacing: 8) {
                        timeField("Start", text: startBinding)
                        Text("→").foregroundStyle(DesignTokens.Colors.ink3)
                        timeField("End", text: endBinding)
                    }
                }
                SettingsRow(title: "Days", caption: "Choose the weekdays quiet hours apply.") {
                    HStack(spacing: 6) {
                        ForEach(SettingsPreferencesLogic.weekDays) { day in
                            dayButton(day)
                        }
                    }
                }
                SettingsRow(title: "Timezone", caption: "Used by the server schedule.") {
                    Picker("", selection: timezoneBinding) {
                        ForEach(timezoneChoices, id: \.self) { timezone in
                            Text(timezone).tag(timezone)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 230)
                }
                LastSettingsRow(title: "Critical bypass", caption: "Critical questions bypass quiet hours.") {
                    Toggle("", isOn: criticalBypassBinding)
                        .labelsHidden()
                }
            }
            if let message = SettingsPreferencesLogic.validationMessage(for: preferencesStore.preferences) {
                Text(message)
                    .font(DesignTokens.Fonts.caption)
                    .foregroundStyle(DesignTokens.Colors.neg)
            }
        }
    }

    private var timezoneChoices: [String] {
        let current = SettingsPreferencesLogic.quietHours(from: preferencesStore.preferences).timezone
        let common = ["UTC", "America/Los_Angeles", "America/New_York", "Europe/London", "Asia/Bangkok"]
        return Array(Set(common + [current])).sorted()
    }

    private func timeField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 13).monospaced())
            .frame(width: 62)
    }

    private func dayButton(_ day: QuietHoursDay) -> some View {
        let isSelected = Set(SettingsPreferencesLogic.quietHours(from: preferencesStore.preferences).days)
            .contains(day.index)
        return Button {
            updateQuietHours(SettingsPreferencesLogic.toggledDay(day.index, in: quietHours))
        } label: {
            Text(day.label)
                .font(DesignTokens.Fonts.body)
                .foregroundStyle(isSelected ? DesignTokens.Colors.paper : DesignTokens.Colors.ink2)
                .frame(width: 26, height: 26)
                .background(isSelected ? DesignTokens.Colors.ink : DesignTokens.Colors.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isSelected ? .clear : DesignTokens.Colors.line2, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var quietHours: QuietHours {
        SettingsPreferencesLogic.quietHours(from: preferencesStore.preferences)
    }

    private var enabledBinding: Binding<Bool> {
        Binding {
            quietHours.enabled
        } set: { value in
            updateQuietHours(quietHours.with(enabled: value))
        }
    }

    private var criticalBypassBinding: Binding<Bool> {
        Binding {
            quietHours.criticalBypass
        } set: { value in
            updateQuietHours(quietHours.with(criticalBypass: value))
        }
    }

    private var startBinding: Binding<String> {
        Binding {
            quietHours.start
        } set: { value in
            updateQuietHours(quietHours.with(start: value))
        }
    }

    private var endBinding: Binding<String> {
        Binding {
            quietHours.end
        } set: { value in
            updateQuietHours(quietHours.with(end: value))
        }
    }

    private var timezoneBinding: Binding<String> {
        Binding {
            quietHours.timezone
        } set: { value in
            updateQuietHours(quietHours.with(timezone: value))
        }
    }

    private func updateQuietHours(_ quietHours: QuietHours) {
        preferencesStore.preferences = SettingsPreferencesLogic.preferences(
            preferencesStore.preferences,
            byUpdating: quietHours
        )
    }
}

private extension QuietHours {
    func with(
        enabled: Bool? = nil,
        start: String? = nil,
        end: String? = nil,
        timezone: String? = nil,
        criticalBypass: Bool? = nil
    ) -> QuietHours {
        QuietHours(
            enabled: enabled ?? self.enabled,
            start: start ?? self.start,
            end: end ?? self.end,
            timezone: timezone ?? self.timezone,
            days: days,
            criticalBypass: criticalBypass ?? self.criticalBypass
        )
    }
}
