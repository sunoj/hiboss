// Boss-visible agent identity and optional registered avatar.
// Exports BossAgent, AgentsServing, and the authenticated HibossAPI agents fetch.
// Dependencies: Foundation Codable and the existing boss API decoder.

import Foundation

public struct BossAgent: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, name
        case avatarURL = "avatar_url"
    }

    public init(id: String, name: String, avatarURL: URL? = nil) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
    }
}

public protocol AgentsServing: Sendable {
    func fetchAgents() async throws -> [BossAgent]
}

extension HibossAPI: AgentsServing {
    public func fetchAgents() async throws -> [BossAgent] {
        let response = try await decode(AgentsResponse.self,
            from: apiURL.appendingPathComponent("agents"), context: "agents")
        return response.agents
    }
}

private struct AgentsResponse: Decodable {
    let agents: [BossAgent]
}
