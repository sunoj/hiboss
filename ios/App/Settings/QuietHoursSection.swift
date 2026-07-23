// Quiet-hours editor: mute window, start/end times, and critical bypass.
// Exports: QuietHoursSection editing PreferencesStore.quietHours.
// Dependencies: SwiftUI, HibossKit, theme tokens.

import HibossKit
import SwiftUI

struct QuietHoursSection: View {
    @ObservedObject var store: PreferencesStore

    private var hours: QuietHours { store.quietHours }

    var body: some View {
        SettingsSection(title: "QUIET HOURS") {
            toggleRow(
                "Mute notifications",
                isOn: hours.enabled,
                set: { on in store.updateQuietHours { $0.with(enabled: on) } }
            )
            if hours.enabled {
                SettingsDivider()
                timeRow("From", value: hours.start) { new in
                    store.updateQuietHours { $0.with(start: new) }
                }
                SettingsDivider()
                timeRow("To", value: hours.end) { new in
                    store.updateQuietHours { $0.with(end: new) }
                }
                SettingsDivider()
                toggleRow(
                    "Let critical through",
                    isOn: hours.criticalBypass,
                    set: { on in store.updateQuietHours { $0.with(criticalBypass: on) } }
                )
            }
        }
    }

    private func toggleRow(_ label: String, isOn: Bool, set: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: set)) {
            Text(label).font(.hbBody).foregroundStyle(Theme.ink)
        }
        .tint(Theme.positive)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func timeRow(
        _ label: String, value: String, set: @escaping (String) -> Void
    ) -> some View {
        HStack {
            Text(label).font(.hbBody).foregroundStyle(Theme.ink)
            Spacer()
            DatePicker(
                "", selection: Binding(
                    get: { QuietTime.date(from: value) },
                    set: { set(QuietTime.string(from: $0)) }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

enum QuietTime {
    static func date(from hhmm: String) -> Date {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        var components = DateComponents()
        components.hour = parts.first ?? 0
        components.minute = parts.count > 1 ? parts[1] : 0
        return Calendar.current.date(from: components) ?? Date()
    }

    static func string(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
