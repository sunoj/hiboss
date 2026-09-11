// Authenticated client minting, inventory, and cascade revocation calls.
// Exports: HibossAPI conformance to BossClientsServing.
// Dependencies: Foundation networking and shared API request helpers.

import Foundation

extension HibossAPI: BossClientsServing {
    public func createClient(kind: BossClientKind, label: String) async throws -> BossClientGrant {
        var request = authorizedRequest(url: apiURL.appendingPathComponent("clients"), method: "POST")
        request.httpBody = try JSONEncoder().encode(ClientRegistration(kind: kind, label: label))
        let (data, response) = try await session.data(for: request)
        try validate(response)
        do {
            let grant = try decoder.decode(BossClientGrant.self, from: data)
            guard !grant.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw HibossAPIError.invalidResponse
            }
            return grant
        } catch {
            // A malformed response may contain the minted bearer. Never echo it.
            throw HibossAPIError.invalidResponse
        }
    }

    public func listClients() async throws -> [BossClient] {
        let response = try await decode(
            ClientInventory.self, from: apiURL.appendingPathComponent("clients"), context: "devices"
        )
        return response.clients
    }

    public func revokeClient(id: BossClientID) async throws {
        try await send("DELETE", url: apiURL.appendingPathComponent("clients").appendingPathComponent(id.rawValue))
    }
}

private struct ClientRegistration: Encodable {
    let kind: BossClientKind
    let label: String
}

private struct ClientInventory: Decodable {
    let clients: [BossClient]
}
