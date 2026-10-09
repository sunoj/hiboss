// Session project identity and the boss session inventory API.
// Exports ProjectSession, SessionsServing and HibossAPI conformance.
import Foundation

public struct ProjectSession: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let projectId: String?
    public let projectSlug: String?
    public let projectRef: ProjectIdentity?
    public let branch: String?
    public let label: String?
    /// Facts the session inventory reports; nil when an older server omits them or
    /// sends a malformed value, so one bad field never drops the session list.
    public let host: String?
    public let agentName: String?
    public let status: String?
    public let statusText: String?
    public let startedAt: String?
    public let lastSeenAt: String?

    public var displayLabel: String {
        guard let slug = projectRef?.slug ?? projectSlug else { return label ?? String(id.prefix(8)) }
        guard let branch, !branch.isEmpty else { return slug }
        return "\(slug)/\(branch)"
    }

    enum CodingKeys: String, CodingKey {
        case id, branch, label
        case projectId = "project_id"
        case projectSlug = "project_slug"
        case projectRef = "project_ref"
        case host, status
        case agentName = "agent_name"
        case statusText = "status_text"
        case startedAt = "started_at"
        case lastSeenAt = "last_seen_at"
    }

    public init(
        id: String, projectId: String?, projectSlug: String?, branch: String?, label: String? = nil,
        projectRef: ProjectIdentity? = nil, host: String? = nil, agentName: String? = nil,
        status: String? = nil, statusText: String? = nil, startedAt: String? = nil, lastSeenAt: String? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.projectSlug = projectSlug
        self.projectRef = projectRef
        self.branch = branch
        self.label = label
        self.host = host
        self.agentName = agentName
        self.status = status
        self.statusText = statusText
        self.startedAt = startedAt
        self.lastSeenAt = lastSeenAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        projectId = try values.decodeIfPresent(String.self, forKey: .projectId)
        projectSlug = try values.decodeIfPresent(String.self, forKey: .projectSlug)
        projectRef = try values.decodeIfPresent(ProjectIdentity.self, forKey: .projectRef)
        branch = try values.decodeIfPresent(String.self, forKey: .branch)
        label = try values.decodeIfPresent(String.self, forKey: .label)
        func optional(_ key: CodingKeys) -> String? { (try? values.decodeIfPresent(String.self, forKey: key)) ?? nil }
        host = optional(.host)
        agentName = optional(.agentName)
        status = optional(.status)
        statusText = optional(.statusText)
        startedAt = optional(.startedAt)
        lastSeenAt = optional(.lastSeenAt)
    }
}

public protocol SessionsServing: Sendable {
    func projectSessions() async throws -> [ProjectSession]
}

extension HibossAPI: SessionsServing {
    public func projectSessions() async throws -> [ProjectSession] {
        let url = apiURL.appendingPathComponent("sessions").appending(
            queryItems: [URLQueryItem(name: "include_inactive", value: "true")]
        )
        return try await decode(ProjectSessionsResponse.self, from: url, context: "sessions").sessions
    }
}

private struct ProjectSessionsResponse: Decodable {
    let sessions: [ProjectSession]
}
