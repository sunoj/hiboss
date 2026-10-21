// Sends this phone's APNs token the way the connected server pushes: direct, relay or not at all.
// Exports: PushRoute and PushRouteOutcome, used by PushManager.register(deviceToken:).
// Dependencies: HibossKit (PushMode, HibossAPI), PushRelayRegistrar. Never logs secrets.

import Foundation
import HibossKit
import os

private let routeLog = Logger(subsystem: "ai.hiboss.app", category: "Push")

struct PushRouteOutcome: Equatable {
    let mode: PushMode?
    let registration: DeviceRegistration
}

@MainActor
enum PushRoute {
    static func register(token: String, bundleId: String, environment: String, api: HibossAPI,
                         relay: PushRelayRegistrar) async -> PushRouteOutcome {
        let mode: PushMode
        do {
            mode = try await api.fetchPushMode()
        } catch {
            routeLog.error("push mode unavailable")
            return PushRouteOutcome(mode: nil, registration: .failed(error.localizedDescription))
        }
        do {
            switch mode {
            case .direct:
                await relay.unregister(api: api)
                try await api.registerDevice(token: token, bundleId: bundleId, environment: environment)
            case .relay:
                try await relay.register(apnsToken: token, environment: environment, bundleId: bundleId, api: api)
            case .unavailable:
                await relay.unregister(api: api)
                return PushRouteOutcome(mode: mode, registration: .idle)
            }
            routeLog.info("registered this phone for \(mode.rawValue) push")
            return PushRouteOutcome(mode: mode, registration: .registered)
        } catch {
            routeLog.error("device registration failed for \(mode.rawValue) push")
            return PushRouteOutcome(mode: mode, registration: .failed(message(for: error)))
        }
    }

    private static func message(for error: Error) -> String {
        guard error is PushRelayError else { return error.localizedDescription }
        return String(localized: "The HiBoss push relay is unavailable. Try again later.")
    }
}
