// Client mirror of the server's boss push rules, so a local notifier alerts as the iPhone would.
// Exports: MessageAlert and MessageAlertPolicy (status tiers, decision tiers, quiet hours).
// Dependencies: Foundation and BossPreferences; server/src/push/boss-payload.ts is the source.

import Foundation

public struct MessageAlert: Equatable, Sendable {
    public let sound: Bool
    public let level: PushLevel

    public init(sound: Bool, level: PushLevel) {
        self.sound = sound
        self.level = level
    }
}

public enum MessageAlertPolicy {
    /// An agent message that is not a decision alert: the status tier for its priority, then the
    /// boss's per-priority override; non-urgent messages wait out quiet hours. nil means no alert.
    public static func messageAlert(priority: String, preferences: BossPreferences, now: Date) -> MessageAlert? {
        let parsed = MessagePriority(rawValue: priority)
        let urgent = parsed == .critical || parsed == .high
        if !urgent, isQuiet(preferences.quietHours, at: now) { return nil }
        return alert(parsed.flatMap { preferences.push?[$0] } ?? statusTier(parsed))
    }

    /// A blocking request: loud while decision alerts are on, otherwise the status tier; the
    /// boss's per-priority override applies either way (server `decisionPushTier`).
    public static func decisionAlert(
        priority: String, preferences: BossPreferences, now: Date = Date()
    ) -> MessageAlert? {
        let parsed = MessagePriority(rawValue: priority)
        if parsed != .high, parsed != .critical, isQuiet(preferences.quietHours, at: now) { return nil }
        let base: PushRule = preferences.decisionAlerts == false ? statusTier(parsed)
            : PushRule(deliver: true, sound: true, level: parsed == .critical ? .timeSensitive : .active)
        return alert(parsed.flatMap { preferences.push?[$0] } ?? base)
    }

    /// Server `isInQuietHours`: an explicit `enabled: false` turns the window off; days and
    /// critical bypass are not consulted, and an unknown time zone falls back to UTC.
    public static func isQuiet(_ quietHours: QuietHours?, at now: Date) -> Bool {
        guard let quietHours, quietHours.enabled,
              let start = minutes(quietHours.start), let end = minutes(quietHours.end), start != end else {
            return false
        }
        var calendar = Calendar(identifier: .gregorian)
        let timezone = quietHours.timezone.trimmingCharacters(in: .whitespacesAndNewlines)
        calendar.timeZone = TimeZone(identifier: timezone) ?? TimeZone(identifier: "UTC") ?? .current
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let current = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return start < end ? current >= start && current < end : current >= start || current < end
    }

    private static func statusTier(_ priority: MessagePriority?) -> PushRule {
        switch priority {
        case .critical: PushRule(deliver: true, sound: true, level: .timeSensitive)
        case .high: PushRule(deliver: true, sound: true, level: .active)
        case .low: PushRule(deliver: false, sound: false, level: .passive)
        case .normal, nil: PushRule(deliver: true, sound: false, level: .passive)
        }
    }

    private static func alert(_ tier: PushRule) -> MessageAlert? {
        return tier.deliver ? MessageAlert(sound: tier.sound, level: tier.level) : nil
    }

    private static func minutes(_ value: String) -> Int? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.count == 2 }),
              let hours = Int(parts[0]), let minutes = Int(parts[1]),
              (0..<24).contains(hours), (0..<60).contains(minutes) else { return nil }
        return hours * 60 + minutes
    }
}
