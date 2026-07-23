// Quiet-hours editor: mute window, start/end times, and critical bypass.
// Exports: QuietHoursSection as a native Form section bound to PreferencesStore.
// Dependencies: SwiftUI, HibossKit.

import HibossKit
import SwiftUI

struct QuietHoursSection: View {
    @ObservedObject var store: PreferencesStore

    private var hours: QuietHours { store.quietHours }

    var body: some View {
        Section {
            Toggle("Mute Notifications", isOn: enabledBinding)
            if hours.enabled {
                DatePicker("From", selection: startBinding, displayedComponents: .hourAndMinute)
                    .environment(\.calendar, QuietTime.calendar)
                DatePicker("To", selection: endBinding, displayedComponents: .hourAndMinute)
                    .environment(\.calendar, QuietTime.calendar)
                Toggle("Let Critical Through", isOn: bypassBinding)
            }
        } header: {
            Text("Quiet Hours")
        } footer: {
            if hours.enabled { Text("Times are in \(hours.timezone).") }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { hours.enabled }, set: { on in store.updateQuietHours { $0.with(enabled: on) } })
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { QuietTime.date(from: hours.start) },
            set: { date in store.updateQuietHours { $0.with(start: QuietTime.string(from: date)) } }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { QuietTime.date(from: hours.end) },
            set: { date in store.updateQuietHours { $0.with(end: QuietTime.string(from: date)) } }
        )
    }

    private var bypassBinding: Binding<Bool> {
        Binding(get: { hours.criticalBypass }, set: { on in store.updateQuietHours { $0.with(criticalBypass: on) } })
    }
}

/// Converts wall-clock "HH:mm" strings to/from a `Date` using a fixed UTC
/// calendar, so the picker edits pure clock digits independent of device tz.
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
