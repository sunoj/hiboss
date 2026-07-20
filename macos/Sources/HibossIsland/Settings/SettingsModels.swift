// Testable models and transforms for the native Settings scene.
// Exports: SettingsPane, SettingsPreferencesLogic, and SettingsPreferencesService.
// Dependencies: HibossKit preferences, AppSettings, and Foundation time zones.

import Foundation
import HibossKit
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case connection
    case notifications
    case routing
    case quietHours
    case presentation
    case systemDoctor
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connection: "Connection"
        case .notifications: "Notifications"
        case .routing: "Channels & Routing"
        case .quietHours: "Quiet Hours"
        case .presentation: "Presentation"
        case .systemDoctor: "System & Doctor"
        case .about: "About"
        }
    }

    var subtitle: String {
        switch self {
        case .connection: "Connect this Mac to the boss daemon."
        case .notifications: "Choose how questions surface on this Mac."
        case .routing: "Route each priority to server-backed channels."
        case .quietHours: "Silence lower-priority alerts on your schedule."
        case .presentation: "Tune the local option surface and sounds."
        case .systemDoctor: "Inspect daemon, stream, and preference health."
        case .about: "Version and project information."
        }
    }

    var icon: String {
        switch self {
        case .connection: "link"
        case .notifications: "bell"
        case .routing: "point.3.connected.trianglepath.dotted"
        case .quietHours: "moon"
        case .presentation: "rectangle.on.rectangle"
        case .systemDoctor: "stethoscope"
        case .about: "info.circle"
        }
    }
}

enum SettingsValidationError: LocalizedError, Equatable {
    case invalidTime(String)

    var errorDescription: String? {
        switch self {
        case let .invalidTime(label): "Enter a valid \(label) time as HH:mm."
        }
    }
}

enum SettingsPreferencesLogic {
    static let priorities: [MessagePriority] = [.critical, .high, .normal, .low]
    static let channels: [NotificationChannel] = [.discord, .telegram, .api]
    static let weekDays: [QuietHoursDay] = [
        QuietHoursDay(index: 1, label: "M"),
        QuietHoursDay(index: 2, label: "T"),
        QuietHoursDay(index: 3, label: "W"),
        QuietHoursDay(index: 4, label: "T"),
        QuietHoursDay(index: 5, label: "F"),
        QuietHoursDay(index: 6, label: "S"),
        QuietHoursDay(index: 7, label: "S"),
    ]

    static let defaultRouting: [MessagePriority: [NotificationChannel]] = [
        .critical: [.discord, .telegram, .api],
        .high: [.telegram],
        .normal: [.discord],
        .low: [.discord],
    ]

    static func selectedPane(
        _ requested: SettingsPane?,
        available: [SettingsPane] = SettingsPane.allCases
    ) -> SettingsPane {
        guard let requested, available.contains(requested) else { return .connection }
        return requested
    }

    static func routing(
        from preferences: BossPreferences
    ) -> [MessagePriority: [NotificationChannel]] {
        preferences.routing ?? defaultRouting
    }

    static func toggledRouting(
        _ routing: [MessagePriority: [NotificationChannel]],
        priority: MessagePriority,
        channel: NotificationChannel
    ) -> [MessagePriority: [NotificationChannel]] {
        var next = routing
        var channels = Set(next[priority] ?? [])
        if channels.contains(channel) {
            channels.remove(channel)
        } else {
            channels.insert(channel)
        }
        next[priority] = Self.channels.filter { channels.contains($0) }
        return next
    }

    static func preferences(
        _ preferences: BossPreferences,
        byUpdating routing: [MessagePriority: [NotificationChannel]]
    ) -> BossPreferences {
        BossPreferences(routing: routing, quietHours: preferences.quietHours)
    }

    static func quietHours(from preferences: BossPreferences) -> QuietHours {
        preferences.quietHours ?? defaultQuietHours()
    }

    static func toggledDay(_ day: Int, in quietHours: QuietHours) -> QuietHours {
        var days = Set(quietHours.days)
        if days.contains(day) {
            days.remove(day)
        } else {
            days.insert(day)
        }
        return QuietHours(
            enabled: quietHours.enabled,
            start: quietHours.start,
            end: quietHours.end,
            timezone: quietHours.timezone,
            days: days.sorted(),
            criticalBypass: quietHours.criticalBypass
        )
    }

    static func isValidClockTime(_ value: String) -> Bool {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return false
        }
        return (0...23).contains(hour) && (0...59).contains(minute)
            && parts[0].count == 2 && parts[1].count == 2
    }

    static func validatedQuietHours(_ quietHours: QuietHours) -> Result<QuietHours, SettingsValidationError> {
        guard isValidClockTime(quietHours.start) else {
            return .failure(.invalidTime("start"))
        }
        guard isValidClockTime(quietHours.end) else {
            return .failure(.invalidTime("end"))
        }
        return .success(quietHours)
    }

    static func preferences(
        _ preferences: BossPreferences,
        byUpdating quietHours: QuietHours
    ) -> BossPreferences {
        BossPreferences(routing: routing(from: preferences), quietHours: quietHours)
    }

    static func validationMessage(for preferences: BossPreferences) -> String? {
        switch validatedQuietHours(quietHours(from: preferences)) {
        case .success: nil
        case let .failure(error): error.localizedDescription
        }
    }

    static func defaultQuietHours(
        timezone: String = TimeZone.current.identifier
    ) -> QuietHours {
        QuietHours(
            enabled: false,
            start: "22:00",
            end: "07:00",
            timezone: timezone,
            days: weekDays.map(\.index),
            criticalBypass: true
        )
    }
}

struct QuietHoursDay: Equatable, Identifiable {
    let index: Int
    let label: String

    var id: Int { index }
}

final class SettingsPreferencesService: BossPreferencesServing, @unchecked Sendable {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func fetchPreferences() async throws -> BossPreferences {
        let api = try await makeAPI()
        return try await api.fetchPreferences()
    }

    func updatePreferences(_ preferences: BossPreferences) async throws -> BossPreferences {
        let api = try await makeAPI()
        return try await api.updatePreferences(preferences)
    }

    private func makeAPI() async throws -> HibossAPI {
        let config = try await MainActor.run {
            try settings.connectionConfig().get()
        }
        return HibossAPI(config: config)
    }
}
