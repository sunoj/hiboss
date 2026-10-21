// Keeps this install's relay registration and the server's copy of it in step.
// Exports: PushRelayRegistrar — register / rotate on token change / unregister on sign-out.
// Dependencies: CryptoKit, HibossKit, PushRelayClient, RelayCredentialStoring.

import CryptoKit
import Foundation
import HibossKit

@MainActor
final class PushRelayRegistrar {
    private let client: PushRelayClient
    private let store: any RelayCredentialStoring
    private var inFlight: Task<Void, Error>?

    init(client: PushRelayClient = PushRelayClient(),
         store: any RelayCredentialStoring = KeychainRelayCredentialStore()) {
        self.client = client
        self.store = store
    }

    var hasRegistration: Bool { (try? store.read()) != nil }

    /// Registers with the relay once, PUTs a rotated APNs token, then (re)sends the handle and
    /// push key to the server. Concurrent calls share one attempt.
    func register(apnsToken: String, environment: String, bundleId: String, api: HibossAPI) async throws {
        if let inFlight { return try await inFlight.value }
        let task = Task { try await self.performRegister(apnsToken: apnsToken, environment: environment,
                                                         bundleId: bundleId, api: api) }
        inFlight = task
        defer { inFlight = nil }
        try await task.value
    }

    /// Deletes the registration at the relay and the server, then erases the local credentials
    /// even when either delete fails: a stale handle only reaches the generic alert.
    func unregister(api: HibossAPI?) async {
        guard let credentials = try? store.read() else { return }
        try? await client.delete(deviceSecret: credentials.deviceSecret)
        if let api { try? await api.deleteDevice(id: credentials.serverDeviceID) }
        try? store.delete()
    }

    private func performRegister(apnsToken: String, environment: String, bundleId: String,
                                 api: HibossAPI) async throws {
        var credentials = try store.read()
        if var current = credentials, current.apnsToken != apnsToken || current.environment != environment {
            do {
                try await client.update(deviceSecret: current.deviceSecret, apnsToken: apnsToken,
                                        environment: environment)
                current.apnsToken = apnsToken
                current.environment = environment
                try store.write(current)
                credentials = current
            } catch PushRelayError.gone {
                try? await api.deleteDevice(id: current.serverDeviceID)
                try store.delete()
                credentials = nil
            }
        }
        let active: RelayCredentials
        if let credentials {
            active = credentials
        } else {
            active = try await freshRegistration(apnsToken: apnsToken, environment: environment)
        }
        try await api.registerRelayDevice(relayHandle: active.handle, pushKey: active.pushKey,
                                          bundleId: bundleId, environment: environment)
    }

    private func freshRegistration(apnsToken: String, environment: String) async throws -> RelayCredentials {
        let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let minted = try await client.register(apnsToken: apnsToken, environment: environment)
        let credentials = RelayCredentials(handle: minted.handle, deviceSecret: minted.deviceSecret,
                                           pushKey: Base64URL.encode(key), apnsToken: apnsToken,
                                           environment: environment)
        try store.write(credentials)
        return credentials
    }
}
