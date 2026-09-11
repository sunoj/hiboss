// Loads device inventory and serializes revocation with current-device protection.
// Exports: BossClientsStore for the shared native Settings section.
// Dependencies: Combine and injectable BossClientsServing.

import Combine
import Foundation

@MainActor
public final class BossClientsStore: ObservableObject {
    @Published public private(set) var clients: [BossClient] = []
    @Published public private(set) var isBusy = false
    @Published public private(set) var error: String?
    private let api: any BossClientsServing

    public init(api: any BossClientsServing) { self.api = api }

    public func load() async {
        guard !isBusy else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do { clients = try await api.listClients() }
        catch { self.error = error.localizedDescription }
    }

    public func revoke(_ client: BossClient) async {
        guard !isBusy, clients.contains(where: { $0.id == client.id && $0.canRevoke }) else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            try await api.revokeClient(id: client.id)
            if let index = clients.firstIndex(where: { $0.id == client.id }) {
                clients[index].revokedAt = Date.now.ISO8601Format()
                clients[index].hasPushDevice = false
            }
            clients = try await api.listClients()
        } catch { self.error = error.localizedDescription }
    }
}
