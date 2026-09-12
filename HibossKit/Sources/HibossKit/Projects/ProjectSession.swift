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
    }

    public init(id: String, projectId: String?, projectSlug: String?, branch: String?, label: String? = nil, projectRef: ProjectIdentity? = nil) {
        self.id = id
        self.projectId = projectId
        self.projectSlug = projectSlug
        self.projectRef = projectRef
        self.branch = branch
        self.label = label
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
