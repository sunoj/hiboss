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

    public var localizedTitle: String {
        switch self {
        case .critical: kitL("Critical")
        case .high: kitL("High")
        case .normal: kitL("Normal")
        case .low: kitL("Low")
        }
    }
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

    public init(from decoder: Decoder) throws {
        try self.init(values: decoder.container(keyedBy: CodingKeys.self))
    }

    init(values: KeyedDecodingContainer<CodingKeys>?, start: String? = nil,
         end: String? = nil, timezone: String? = nil) throws {
        enabled = try values?.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.start = try start ?? values?.decodeIfPresent(String.self, forKey: .start) ?? ""
        self.end = try end ?? values?.decodeIfPresent(String.self, forKey: .end) ?? ""
        self.timezone = try values?.decodeIfPresent(String.self, forKey: .timezone) ?? timezone ?? "UTC"
        days = try values?.decodeIfPresent([Int].self, forKey: .days) ?? [0, 1, 2, 3, 4, 5, 6]
        criticalBypass = try values?.decodeIfPresent(Bool.self, forKey: .criticalBypass) ?? true
    }
}

/// How intrusive a push should be for a given message priority.
public enum PushLevel: String, Codable, Equatable, Sendable, CaseIterable {
    case passive
    case active
    case timeSensitive = "time-sensitive"
}

/// Per-priority push override: whether to deliver, whether to sound, how loud.
public struct PushRule: Codable, Equatable, Sendable {
    public var deliver: Bool
    public var sound: Bool
    public var level: PushLevel

    public init(deliver: Bool, sound: Bool, level: PushLevel) {
        self.deliver = deliver
        self.sound = sound
        self.level = level
    }
}

public struct BossPreferences: Codable, Equatable, Sendable {
    public var routing: [MessagePriority: [NotificationChannel]]?
    public var quietHours: QuietHours?
    /// Per-priority push tiering overrides for status messages (nil = server defaults).
    public var push: [MessagePriority: PushRule]?
    /// When true, pushes carry only a generic alert + message id; the app fetches
    /// the body over TLS so content never reaches Apple's servers.
    public var privatePush: Bool?
    /// When false, decision requests follow normal push tiering and skip Live Activities.
    public var decisionAlerts: Bool?
    private let preservedRouting: [String: [String]]?

    enum CodingKeys: String, CodingKey {
        case routing
        case quietHours = "quiet_hours"
        case quietStart = "quiet_hours_start"
        case quietEnd = "quiet_hours_end"
        case timezone
        case push
        case privatePush = "private_push"
        case decisionAlerts = "decision_alerts"
    }

    public init(
        routing: [MessagePriority: [NotificationChannel]]? = nil,
        quietHours: QuietHours? = nil,
        push: [MessagePriority: PushRule]? = nil,
        privatePush: Bool? = nil,
        decisionAlerts: Bool? = nil
    ) {
        self.routing = routing
        self.quietHours = quietHours
        self.push = push
        self.privatePush = privatePush
        self.decisionAlerts = decisionAlerts
        self.preservedRouting = nil
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        quietHours = try Self.decodeQuietHours(values: values)
        let decodedRouting = try Self.decodeRouting(from: values)
        routing = decodedRouting.typed
        preservedRouting = decodedRouting.raw
        push = try Self.decodePush(from: values)
        privatePush = try values.decodeIfPresent(Bool.self, forKey: .privatePush)
        decisionAlerts = try values.decodeIfPresent(Bool.self, forKey: .decisionAlerts)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(quietHours, forKey: .quietHours)
        try encodeRouting(into: &values)
        try encodePush(into: &values)
        try values.encodeIfPresent(privatePush, forKey: .privatePush)
        try values.encodeIfPresent(decisionAlerts, forKey: .decisionAlerts)
    }

    public static func == (lhs: BossPreferences, rhs: BossPreferences) -> Bool {
        lhs.routing == rhs.routing && lhs.quietHours == rhs.quietHours
            && lhs.push == rhs.push && lhs.privatePush == rhs.privatePush
            && lhs.decisionAlerts == rhs.decisionAlerts
    }

    private static func decodeQuietHours(
        values: KeyedDecodingContainer<CodingKeys>
    ) throws -> QuietHours? {
        let start = try values.decodeIfPresent(String.self, forKey: .quietStart)
        let end = try values.decodeIfPresent(String.self, forKey: .quietEnd)
        let hasNested = try values.contains(.quietHours) && !values.decodeNil(forKey: .quietHours)
        guard hasNested || start != nil || end != nil else { return nil }
        let nested = try hasNested
            ? values.nestedContainer(keyedBy: QuietHours.CodingKeys.self, forKey: .quietHours)
            : nil
        return try QuietHours(values: nested, start: start, end: end,
            timezone: values.decodeIfPresent(String.self, forKey: .timezone))
    }

    private static func decodePush(
        from values: KeyedDecodingContainer<CodingKeys>
    ) throws -> [MessagePriority: PushRule]? {
        guard let raw = try values.decodeIfPresent([String: PushRule].self, forKey: .push) else {
            return nil
        }
        var push: [MessagePriority: PushRule] = [:]
        for (rawPriority, rule) in raw {
            guard let priority = MessagePriority(rawValue: rawPriority) else { continue }
            push[priority] = rule
        }
        return push
    }

    private func encodePush(into values: inout KeyedEncodingContainer<CodingKeys>) throws {
        guard let push else { return }
        let raw = Dictionary(uniqueKeysWithValues: push.map { ($0.key.rawValue, $0.value) })
        try values.encode(raw, forKey: .push)
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
