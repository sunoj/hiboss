// Native Settings chrome: not-applied notice, footer status, and label helpers.
// Exports: SettingsNotAppliedNotice, SettingsFooterStatus, routing label extensions.
// Dependencies: SwiftUI, HibossKit, and DesignTokens priority/live accents.

import HibossKit
import SwiftUI

/// States plainly that a pane's settings are stored but not yet acted on.
/// These preferences persist to the server, but nothing consults them at delivery time
/// yet — showing the controls without saying so would make them read as working switches.
struct SettingsNotAppliedNotice: View {
    var body: some View {
        Label {
            Text(
                "Saved, but not applied yet. Delivery still follows each agent's channel "
                    + "configuration; these preferences take effect in a later release."
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
        return String(format: "%02d:%02d", hour, minute)
    }

    static func weekdayTitle(dayIndex: Int) -> String {
        switch dayIndex {
        case 1: "Monday"
        case 2: "Tuesday"
        case 3: "Wednesday"
        case 4: "Thursday"
        case 5: "Friday"
        case 6: "Saturday"
        case 7: "Sunday"
        default: "Day \(dayIndex)"
        }
    }
}

extension MessagePriority {
    var settingsLabel: String { rawValue }

    var settingsColor: Color {
        switch self {
        case .critical: DesignTokens.Priority.critical
        case .high: DesignTokens.Priority.high
        case .normal: DesignTokens.Priority.normal
        case .low: DesignTokens.Priority.low
        }
    }
}

extension NotificationChannel {
    var settingsLabel: String {
        switch self {
        case .discord: "Discord"
        case .telegram: "Telegram"
        case .api: "API"
        }
    }
}
