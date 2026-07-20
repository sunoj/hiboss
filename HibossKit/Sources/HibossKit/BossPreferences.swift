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
    public var routing: [MessagePriority: [NotificationChannel]]?
    public var quietHours: QuietHours?
    private let preservedRouting: [String: [String]]?

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
        self.preservedRouting = nil
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        quietHours = try values.decodeIfPresent(QuietHours.self, forKey: .quietHours)
        let decodedRouting = try Self.decodeRouting(from: values)
        routing = decodedRouting.typed
        preservedRouting = decodedRouting.raw
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(quietHours, forKey: .quietHours)
        try encodeRouting(into: &values)
    }

    public static func == (lhs: BossPreferences, rhs: BossPreferences) -> Bool {
        lhs.routing == rhs.routing && lhs.quietHours == rhs.quietHours
    }

    private static func decodeRouting(
        from values: KeyedDecodingContainer<CodingKeys>
    ) throws -> (typed: [MessagePriority: [NotificationChannel]]?, raw: [String: [String]]?) {
        guard let rawRouting = try values.decodeIfPresent([String: [String]].self, forKey: .routing) else {
            return (nil, nil)
        }
        var routing: [MessagePriority: [NotificationChannel]] = [:]
        for (rawPriority, rawChannels) in rawRouting {
            guard let priority = MessagePriority(rawValue: rawPriority) else { continue }
            routing[priority] = rawChannels.compactMap(NotificationChannel.init(rawValue:))
        }
        return (routing, rawRouting)
    }

    private func encodeRouting(
        into values: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        guard let routing else { return }
        var rawRouting = preservedRouting?.filter { MessagePriority(rawValue: $0.key) == nil } ?? [:]
        for (priority, channels) in routing {
            rawRouting[priority.rawValue] = mergedChannels(for: priority, channels: channels)
        }
        try values.encode(rawRouting, forKey: .routing)
    }

    private func mergedChannels(
        for priority: MessagePriority,
        channels: [NotificationChannel]
    ) -> [String] {
        let rawChannels = preservedRouting?[priority.rawValue] ?? []
        let unknownChannels = rawChannels.filter { NotificationChannel(rawValue: $0) == nil }
        return channels.map(\.rawValue) + unknownChannels
    }
}
