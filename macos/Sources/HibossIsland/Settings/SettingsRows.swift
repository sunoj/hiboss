// Native Settings chrome: not-applied notice, footer status, and quiet-hours formatting.
// Exports: SettingsNotAppliedNotice, SettingsFooterStatus, QuietHoursClockFormatting.
// Dependencies: SwiftUI and DesignTokens live accents.

import SwiftUI

/// States plainly that a pane's settings are stored but not yet acted on.
/// These preferences persist to the server, but nothing consults them at delivery time
/// yet — showing the controls without saying so would make them read as working switches.
struct SettingsNotAppliedNotice: View {
    var body: some View {
        Label {
            Text(
                L(
                    "Saved, but not applied yet. Delivery still follows each agent's channel configuration; these preferences take effect in a later release."
                )
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SettingsFooterStatus: View {
    let text: String
    let isActive: Bool
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: isActive ? "circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(isActive ? DesignTokens.live : Color(nsColor: .tertiaryLabelColor))
            }
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }
}

enum QuietHoursClockFormatting {
    static func date(fromClock clock: String, reference: Date = .now) -> Date {
        let parts = clock.split(separator: ":", omittingEmptySubsequences: false)
        var components = Calendar.current.dateComponents([.year, .month, .day], from: reference)
        if parts.count == 2,
           let hour = Int(parts[0]),
           let minute = Int(parts[1]),
           (0...23).contains(hour),
           (0...59).contains(minute) {
            components.hour = hour
            components.minute = minute
        } else {
            components.hour = 0
            components.minute = 0
        }
        return Calendar.current.date(from: components) ?? reference
    }

    static func clockString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return String(format: "%02d:%02d", hour, minute) // i18n-exempt: HH:mm storage value
    }

    static func weekdayTitle(dayIndex: Int) -> String {
        switch dayIndex {
        case 1: L("Monday")
        case 2: L("Tuesday")
        case 3: L("Wednesday")
        case 4: L("Thursday")
        case 5: L("Friday")
        case 6: L("Saturday")
        case 7: L("Sunday")
        default: L("Day \(dayIndex)")
        }
    }
}
