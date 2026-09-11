// Boss-owned client inventory and per-client credential contracts.
// Exports: BossClientID, BossClientKind, BossClient, and BossClientGrant.
// Dependencies: Foundation Codable and date parsing.

import Foundation

public struct BossClientID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public enum BossClientKind: String, Codable, Sendable {
    case ios, macos, web, cli

    public var symbol: String {
        switch self {
        case .ios: "iphone"
        case .macos: "desktopcomputer"
        case .web: "globe"
        case .cli: "terminal"
        }
    }
}

public struct BossClient: Decodable, Identifiable, Equatable, Sendable {
    public let id: BossClientID
    public let kind: BossClientKind
    public let label: String
    public let createdAt: String
    public let lastSeenAt: String?
    public internal(set) var revokedAt: String?
    public internal(set) var hasPushDevice: Bool
    public let hasSigningKey: Bool
    public let isCurrent: Bool

    public var canRevoke: Bool { !isCurrent && revokedAt == nil }

    public var lastSeenDate: Date? {
        guard let lastSeenAt else { return nil }
        let timestamp = lastSeenAt.contains("T") ? lastSeenAt
            : lastSeenAt.replacingOccurrences(of: " ", with: "T") + "Z"
        return (try? Date(timestamp, strategy: .iso8601))
            ?? (try? Date(timestamp, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, label
        case createdAt = "created_at"
        case lastSeenAt = "last_seen_at"
        case revokedAt = "revoked_at"
        case hasPushDevice = "has_push_device"
        case hasSigningKey = "has_signing_key"
        case isCurrent = "is_current"
    }
}

public struct BossClientGrant: Decodable, Sendable {
    public let client: BossClient
    public let token: String

    public init(client: BossClient, token: String) {
        self.client = client
        self.token = token
    }
}
