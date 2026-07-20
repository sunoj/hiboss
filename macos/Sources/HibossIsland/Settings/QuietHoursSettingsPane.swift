// Quiet Hours pane for server-backed notification silencing preferences.
// Exports: QuietHoursSettingsPane.
// Dependencies: SwiftUI, HibossKit QuietHours, and settings preference logic.

import HibossKit
import SwiftUI

struct QuietHoursSettingsPane: View {
    @ObservedObject var preferencesStore: BossPreferencesStore

    var body: some View {
        Form {
            Section {
                Toggle("Quiet Hours", isOn: enabledBinding)
                DatePicker(
                    "Starts",
                    selection: startBinding,
                    displayedComponents: .hourAndMinute
                )
                DatePicker(
                    "Ends",
                    selection: endBinding,
                    displayedComponents: .hourAndMinute
                )
                Picker("Timezone", selection: timezoneBinding) {
                    ForEach(timezoneChoices, id: \.self) { timezone in
                        Text(timezone).tag(timezone)
                    }
                }
                Toggle("Critical bypass", isOn: criticalBypassBinding)
            } header: {
                Text("Schedule")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Silence normal & low priority alerts; critical can still alert when bypass is on.")
                        .foregroundStyle(.secondary)
                    SettingsNotAppliedNotice()
                    if let message = SettingsPreferencesLogic.validationMessage(
                        for: preferencesStore.preferences
                    ) {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section {
                ForEach(SettingsPreferencesLogic.weekDays) { day in
                    Toggle(
                        QuietHoursClockFormatting.weekdayTitle(dayIndex: day.index),
                        isOn: dayBinding(day)
                    )
                }
            } header: {
                Text("Days")
            } footer: {
                Text("Choose the weekdays quiet hours apply.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var timezoneChoices: [String] {
        let current = SettingsPreferencesLogic.quietHours(from: preferencesStore.preferences).timezone
        let common = [
            "UTC",
            "America/Los_Angeles",
            "America/New_York",
            "Europe/London",
            "Asia/Bangkok",
        ]
        return Array(Set(common + [current])).sorted()
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

    private var startBinding: Binding<Date> {
        Binding {
            QuietHoursClockFormatting.date(fromClock: quietHours.start)
        } set: { value in
            updateQuietHours(quietHours.with(start: QuietHoursClockFormatting.clockString(from: value)))
        }
    }

    private var endBinding: Binding<Date> {
        Binding {
            QuietHoursClockFormatting.date(fromClock: quietHours.end)
        } set: { value in
            updateQuietHours(quietHours.with(end: QuietHoursClockFormatting.clockString(from: value)))
        }
    }

    private var timezoneBinding: Binding<String> {
        Binding {
            quietHours.timezone
        } set: { value in
            updateQuietHours(quietHours.with(timezone: value))
        }
    }

    private func dayBinding(_ day: QuietHoursDay) -> Binding<Bool> {
        Binding {
            Set(quietHours.days).contains(day.index)
        } set: { _ in
            updateQuietHours(SettingsPreferencesLogic.toggledDay(day.index, in: quietHours))
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
