// Quiet-hours editor: mute window, start/end times, and critical bypass.
// Exports: QuietHoursSection editing PreferencesStore.quietHours.
// Dependencies: SwiftUI, HibossKit, theme tokens.

import HibossKit
import SwiftUI

struct QuietHoursSection: View {
    @ObservedObject var store: PreferencesStore

    private var hours: QuietHours { store.quietHours }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            if hours.enabled {
                Text("Times are in \(hours.timezone).")
                    .font(.hbFootnote).foregroundStyle(Theme.ink4).padding(.leading, 6)
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
            .environment(\.calendar, QuietTime.calendar)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

/// Converts wall-clock "HH:mm" strings to/from a `Date` using a fixed UTC
/// calendar, so the picker edits pure clock digits independent of device
/// timezone. The stored `QuietHours.timezone` decides how the server reads them.
enum QuietTime {
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return cal
    }()

    static func date(from hhmm: String) -> Date {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        let hour = min(max(parts.first ?? 0, 0), 23)
        let minute = min(max(parts.count > 1 ? parts[1] : 0, 0), 59)
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    static func string(from date: Date) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
