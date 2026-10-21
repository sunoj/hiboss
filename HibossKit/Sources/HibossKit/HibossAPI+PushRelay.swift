// Server side of push delivery: the server's push mode and relay device registration.
// Exports: PushMode and HibossAPI.fetchPushMode, registerRelayDevice and deleteDevice.
// Dependencies: Foundation and HibossAPI's authorized request helpers.

import Foundation

/// How the server delivers pushes: its own APNs key, the HiBoss push relay, or not at all.
/// `unavailable` is the wire value `none`, named so it never reads as `Optional.none`.
public enum PushMode: String, Sendable, Equatable {
    case direct, relay
    case unavailable = "none"
}

extension HibossAPI {
    /// Reads `pushMode` from `/api/boss/me`; a server that predates it pushes directly.
    public func fetchPushMode() async throws -> PushMode {
        let me = try await decode(MePushMode.self, from: apiURL.appendingPathComponent("me"),
                                  context: "push mode")
        guard let raw = me.pushMode else { return .direct }
        guard let mode = PushMode(rawValue: raw) else {
            throw HibossAPIError.decodingFailed(context: "push mode", body: raw)
        }
        return mode
    }

    /// Gives the server the relay capability and the key it encrypts this device's pushes with.
    public func registerRelayDevice(
        relayHandle: String,
        pushKey: String,
        bundleId: String,
        environment: String,
        platform: String = "ios"
    ) async throws {
        var request = authorizedRequest(url: apiURL.appendingPathComponent("devices"), method: "POST")
        request.httpBody = try JSONEncoder().encode(RelayDeviceRegistration(
            relayHandle: relayHandle, pushKey: pushKey, environment: environment,
            platform: platform, bundleId: bundleId
        ))
        let (_, response) = try await session.data(for: request)
        try await validate(response)
    }

    /// Deletes one device row; a relay device is addressed as `relay:<handle>`.
    public func deleteDevice(id: String) async throws {
        try await send("DELETE", url: apiURL.appendingPathComponent("devices").appendingPathComponent(id))
    }
}

private struct MePushMode: Decodable {
    let pushMode: String?
}

private struct RelayDeviceRegistration: Encodable {
    let relayHandle: String
    let pushKey: String
    let environment: String
    let platform: String
    let bundleId: String
}
