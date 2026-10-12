// Synthetic registered-device inventory for native Settings refresh regression coverage.
// Exports DemoBossClientsAPI; reads and revocations affect only in-memory demo clients.
// Dependencies: HibossKit, Foundation, and the existing demo refresh delay.

import Foundation
import HibossKit

@MainActor
final class DemoBossClientsAPI: BossClientsServing {
    static let shared = DemoBossClientsAPI()
    private let started = Date()
    private var revoked = false

    func verifyConnection() async throws {}

    func listClients() async throws -> [BossClient] {
        if Date().timeIntervalSince(started) > 5 { try await DemoDelay.wait("REFRESH") }
        let json = """
        [{"id":"demo-phone","kind":"ios","label":"This phone","created_at":"2026-10-01T00:00:00Z",
          "revoked_at":null,"has_push_device":true,"has_signing_key":true,"is_current":true},
         {"id":"demo-mac","kind":"macos","label":"Review Mac","created_at":"2026-10-01T00:00:00Z",
          "revoked_at":\(revoked ? "\"2026-10-12T00:00:00Z\"" : "null"),"has_push_device":false,
          "has_signing_key":true,"is_current":false}]
        """
        return try JSONDecoder().decode([BossClient].self, from: Data(json.utf8))
    }

    func revokeClient(id: BossClientID) async throws { revoked = true }

    func createClient(kind: BossClientKind, label: String) async throws -> BossClientGrant {
        throw HibossAPIError.invalidResponse
    }
}
