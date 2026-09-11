// Verifies manual credentials before exchanging them for a native client token.
// Exports: ManualClientLogin and its explicit compatibility notice.
// Dependencies: BossClientsServing; callers own credential persistence.

import Foundation

public struct ManualClientLogin: Sendable {
    public let config: ConnectionConfig
    public let notice: String?

    public static func exchange(
        config: ConnectionConfig, kind: BossClientKind, label: String,
        api: any BossClientsServing
    ) async throws -> ManualClientLogin {
        try await api.verifyConnection()
        do {
            let grant = try await api.createClient(kind: kind, label: label)
            return ManualClientLogin(
                config: ConnectionConfig(serverURL: config.serverURL, bossToken: grant.token), notice: nil
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return ManualClientLogin(config: config, notice: kitL(
                "Device registration failed. Connected using the pasted token; this server may not support device tokens yet."
            ))
        }
    }
}
