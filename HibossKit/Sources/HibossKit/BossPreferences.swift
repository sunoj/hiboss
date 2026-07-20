// Domain contracts for boss notification routing and quiet hours.
// Exports: BossPreferences, NotificationChannel, MessagePriority, and QuietHours.
// Dependencies: Foundation Codable for API request and response payloads.

import Foundation

public enum NotificationChannel: String, Codable, Equatable, Sendable, CaseIterable {
    case discord
    case telegram
    case api
}

public enum MessagePriority: String, Codable, Equatable, Sendable, CaseIterable, Hashable {
    case critical
    case high
    case normal
    case low
}

public struct QuietHours: Codable, Equatable, Sendable {
    public let enabled: Bool
    public let start: String
    public let end: String
    public let timezone: String
    public let days: [Int]
    public let criticalBypass: Bool

    enum CodingKeys: String, CodingKey {
        case enabled
        case start
        case end
        case timezone
        case days
        case criticalBypass = "critical_bypass"
    }

    public init(
        enabled: Bool,
        start: String,
        end: String,
        timezone: String,
        days: [Int],
        criticalBypass: Bool
    ) {
        self.enabled = enabled
        self.start = start
        self.end = end
        self.timezone = timezone
        self.days = days
        self.criticalBypass = criticalBypass
    }
}

public struct BossPreferences: Codable, Equatable, Sendable {
    public let routing: [MessagePriority: [NotificationChannel]]?
    public let quietHours: QuietHours?

    enum CodingKeys: String, CodingKey {
        case routing
        case quietHours = "quiet_hours"
    }

    public init(
        routing: [MessagePriority: [NotificationChannel]]? = nil,
        quietHours: QuietHours? = nil
    ) {
        self.routing = routing
        self.quietHours = quietHours
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        quietHours = try values.decodeIfPresent(QuietHours.self, forKey: .quietHours)
        routing = try Self.decodeRouting(from: values)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(quietHours, forKey: .quietHours)
        try encodeRouting(into: &values)
    }

    private static func decodeRouting(
        from values: KeyedDecodingContainer<CodingKeys>
    ) throws -> [MessagePriority: [NotificationChannel]]? {
        guard let rawRouting = try values.decodeIfPresent([String: [String]].self, forKey: .routing) else {
            return nil
        }
        var routing: [MessagePriority: [NotificationChannel]] = [:]
        for (rawPriority, rawChannels) in rawRouting {
            guard let priority = MessagePriority(rawValue: rawPriority) else { continue }
            routing[priority] = rawChannels.compactMap(NotificationChannel.init(rawValue:))
        }
        return routing
    }

    private func encodeRouting(
        into values: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        guard let routing else { return }
        var rawRouting: [String: [String]] = [:]
        for (priority, channels) in routing {
            rawRouting[priority.rawValue] = channels.map(\.rawValue)
        }
        try values.encode(rawRouting, forKey: .routing)
    }
}
