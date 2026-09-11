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
    @Published public private(set) var registrationNotice: String?
    @Published private var hasLoaded = false
    private var api: any BossClientsServing

    public init(api: any BossClientsServing) { self.api = api }

    public func load() async {
        guard !isBusy else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            clients = try await api.listClients()
            hasLoaded = true
        }
        catch { self.error = error.localizedDescription }
    }

    public func needsRegistration(kind: BossClientKind) -> Bool {
        hasLoaded && !clients.contains { $0.isCurrent && $0.kind == kind }
    }

    /// Activation must persist credentials before returning the newly authenticated API.
    public func register(
        kind: BossClientKind, label: String,
        activate: @MainActor (String) throws -> any BossClientsServing
    ) async {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isBusy, needsRegistration(kind: kind), !label.isEmpty else { return }
        isBusy = true
        registrationNotice = nil
        error = nil
        defer { isBusy = false }
        do {
            let grant = try await api.createClient(kind: kind, label: label)
            try Task.checkCancellation()
            api = try activate(grant.token)
        } catch {
            registrationNotice = ManualClientLogin.compatibilityNotice
            return
        }
        // A failed refresh must not offer a second registration with stale inventory.
        hasLoaded = false
        do {
            clients = try await api.listClients()
            hasLoaded = true
        } catch { self.error = error.localizedDescription }
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
