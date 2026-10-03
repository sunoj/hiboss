// Pending machine join requests and the boss's approve/reject results.
// Exports: JoinRequest, JoinRequestProfile, JoinApproval, JoinApprovedAgent, JoinRequestError.
// Dependencies: Foundation Codable; copy resolves through the HibossKit catalog.

import Foundation

public struct JoinRequestProfile: Decodable, Equatable, Hashable, Sendable, Identifiable {
    public let profile: String
    public let name: String
    public var id: String { profile + "\u{1F}" + name }

    public init(profile: String, name: String) {
        self.profile = profile
        self.name = name
    }
}

public struct JoinRequest: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let status: String
    public let deviceLabel: String
    public let deviceHost: String?
    public let deviceID: String?
    public let inviterLabel: String?
    public let verificationCode: String?
    public let profiles: [JoinRequestProfile]
    public let createdAt: String
    public let updatedAt: String

    public init(
        id: String, status: String = "pending", deviceLabel: String, deviceHost: String? = nil,
        deviceID: String? = nil, inviterLabel: String? = nil, verificationCode: String?,
        profiles: [JoinRequestProfile] = [], createdAt: String = "", updatedAt: String = ""
    ) {
        self.id = id
        self.status = status
        self.deviceLabel = deviceLabel
        self.deviceHost = deviceHost
        self.deviceID = deviceID
        self.inviterLabel = inviterLabel
        self.verificationCode = verificationCode
        self.profiles = profiles
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, status, profiles
        case deviceLabel = "device_label"
        case deviceHost = "device_host"
        case deviceID = "device_id"
        case inviterLabel = "inviter_label"
        case verificationCode = "verification_code"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// The code the boss compares with the new machine; blank counts as missing.
    public var displayCode: String? {
        guard let code = verificationCode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !code.isEmpty else { return nil }
        return code
    }

    /// Approval needs a code on screen to compare, so a request without one cannot be approved.
    public var canApprove: Bool { displayCode != nil }

    /// Profile names as a short locale-aware list, for example "claude, codex".
    public var profileSummary: String {
        profiles.map(\.profile).formatted(.list(type: .and, width: .narrow))
    }

    /// Accepts SQLite `YYYY-MM-DD HH:MM:SS` (UTC) and ISO 8601 with or without fractions.
    public var createdDate: Date? {
        guard !createdAt.isEmpty else { return nil }
        let timestamp = createdAt.contains("T") ? createdAt
            : createdAt.replacingOccurrences(of: " ", with: "T") + "Z"
        return ISODate.parse(timestamp)
    }
}

public struct JoinApprovedAgent: Decodable, Equatable, Sendable, Identifiable {
    public let profile: String
    public let name: String
    public let agentID: String
    public var id: String { agentID }

    enum CodingKeys: String, CodingKey {
        case profile, name
        case agentID = "agent_id"
    }
}

public struct JoinApproval: Decodable, Equatable, Sendable {
    public let id: String
    public let status: String
    public let deviceID: String?
    public let agents: [JoinApprovedAgent]

    enum CodingKeys: String, CodingKey {
        case id, status, agents
        case deviceID = "device_id"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        status = try values.decode(String.self, forKey: .status)
        deviceID = try values.decodeIfPresent(String.self, forKey: .deviceID)
        agents = try values.decodeIfPresent([JoinApprovedAgent].self, forKey: .agents) ?? []
    }
}

public enum JoinRequestError: Error, Equatable, LocalizedError, Sendable {
    case forbidden
    case conflict(String)
    case notFound

    public var errorDescription: String? {
        switch self {
        case .forbidden:
            kitL("Only an admin can approve devices")
        case let .conflict(message):
            message.isEmpty ? kitL("This request was already processed.") : message
        case .notFound:
            kitL("This request is no longer pending.")
        }
    }
}
