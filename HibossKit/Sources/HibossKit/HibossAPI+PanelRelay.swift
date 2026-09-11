// Ticket issuance for the authenticated boss panel relay connection.
// Exports: PanelConnectionTicket and HibossAPI.issuePanelConnectionTicket.
// Dependencies: HibossAPI request helpers and Foundation Codable.

import Foundation

public struct PanelConnectionTicket: Decodable, Equatable, Sendable {
    public let ticket: String
    public let roomID: String
    public let panelID: String
    public let expiresAt: Int64

    enum CodingKeys: String, CodingKey {
        case ticket, roomID = "roomId", panelID = "panelId", expiresAt
    }
}

extension HibossAPI {
    public func issuePanelConnectionTicket(panelID: String) async throws -> PanelConnectionTicket {
        try await issueConnectionTicket(path: "api/panel-connections", body: PanelConnectionRequest(panelID: panelID, role: "subscriber"))
    }

    public func issuePanelWallConnectionTicket() async throws -> PanelConnectionTicket {
        try await issueConnectionTicket(path: "api/panel-wall-connections", body: [String: String]())
    }

    private func issueConnectionTicket(path: String, body: some Encodable) async throws -> PanelConnectionTicket {
        let endpoint = config.serverURL.appendingPathComponent(path)
        var request = authorizedRequest(url: endpoint, method: "POST")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decoder.decode(PanelConnectionTicket.self, from: data)
    }
}

private struct PanelConnectionRequest: Encodable {
    let panelID: String
    let role: String

    enum CodingKeys: String, CodingKey { case panelID = "panelId", role }
}
