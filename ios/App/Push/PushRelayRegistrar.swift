// Keeps this install's relay registration and the server's copy of it in step.
// Exports: PushRelayRegistrar — confirm or register, rotate, back off, unregister on sign-out.
// Dependencies: CryptoKit, HibossKit, PushRelayClient, RelayCredentialStoring.

import CryptoKit
import Foundation
import HibossKit

@MainActor
final class PushRelayRegistrar {
    private let client: PushRelayClient
    private let store: any RelayCredentialStoring
    private let now: () -> Date
    private var inFlight: Task<Void, Error>?
    private var retryTask: Task<Void, Never>?
    private var rejected: (token: String, environment: String)?
    private var backoff: TimeInterval = 0
    /// After a 503 no relay call is made before this time; the wait doubles up to an hour.
    private(set) var retryAt: Date?

    static let minimumBackoff: TimeInterval = 30
    static let maximumBackoff: TimeInterval = 3_600

    init(client: PushRelayClient = PushRelayClient(),
         store: any RelayCredentialStoring = KeychainRelayCredentialStore(),
         now: @escaping () -> Date = Date.init) {
        self.client = client
        self.store = store
        self.now = now
    }

    var hasRegistration: Bool { (try? store.read()) != nil }

    /// Confirms or creates the relay registration, then (re)sends the handle and push key to the
    /// server. Concurrent calls share one attempt.
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
        retryTask?.cancel()
        guard let credentials = try? store.read() else { return }
        try? await client.delete(deviceSecret: credentials.deviceSecret)
        if let api { try? await api.deleteDevice(id: credentials.serverDeviceID) }
        try? store.delete()
    }

    /// Keeps one pending retry after a relay 503; `nil` cancels it.
    func scheduleRetry(at date: Date?, _ retry: @escaping @MainActor () -> Void) {
        retryTask?.cancel()
        guard let date else { return }
        retryTask = Task {
            try? await Task.sleep(for: .seconds(max(1, date.timeIntervalSince(now()))))
            if !Task.isCancelled { retry() }
        }
    }

    /// Confirms the stored registration (or registers fresh), then gives the server its handle.
    /// A rejected token is not resent until it changes; a 503 holds every relay call until `retryAt`.
    private func performRegister(apnsToken: String, environment: String, bundleId: String,
                                 api: HibossAPI) async throws {
        if let rejected, rejected.token == apnsToken, rejected.environment == environment {
            throw PushRelayError.invalidToken
        }
        if let retryAt, now() < retryAt { throw PushRelayError.unavailable }
        let active: RelayCredentials
        do {
            active = try await confirmedRegistration(apnsToken: apnsToken, environment: environment, api: api)
        } catch PushRelayError.unavailable {
            backoff = min(max(backoff * 2, Self.minimumBackoff), Self.maximumBackoff)
            retryAt = now().addingTimeInterval(backoff)
            throw PushRelayError.unavailable
        } catch PushRelayError.invalidToken {
            rejected = (apnsToken, environment)
            throw PushRelayError.invalidToken
        }
        backoff = 0
        retryAt = nil
        rejected = nil
        try await api.registerRelayDevice(relayHandle: active.handle, pushKey: active.pushKey,
                                          bundleId: bundleId, environment: environment)
    }

    /// `PUT /self` on every pass refreshes the relay's copy; a 410 means the registration was lost
    /// (purged, replaced or rejected by APNs), so the old server row goes and a fresh one is minted.
    private func confirmedRegistration(apnsToken: String, environment: String,
                                       api: HibossAPI) async throws -> RelayCredentials {
        if var current = try store.read() {
            do {
                try await client.update(deviceSecret: current.deviceSecret, apnsToken: apnsToken,
                                        environment: environment)
                if current.apnsToken != apnsToken || current.environment != environment {
                    current.apnsToken = apnsToken
                    current.environment = environment
                    try store.write(current)
                }
                return current
            } catch PushRelayError.gone {
                try? await api.deleteDevice(id: current.serverDeviceID)
                try store.delete()
            }
        }
        return try await freshRegistration(apnsToken: apnsToken, environment: environment)
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
