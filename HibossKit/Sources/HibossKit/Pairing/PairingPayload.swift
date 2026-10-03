// Parses a hiboss://pair link, or a typed server + code, into a redeemable pairing payload.
// Exports: PairingPayload and PairingPayloadError, shared by the iOS and macOS clients.
// Dependencies: Foundation URLComponents and PairingGrant's code-shape check.

import Foundation

public struct PairingPayload: Equatable, Sendable {
    public let serverURL: URL
    public let code: String

    /// The host shown before redeeming, so the boss sees which server receives the code.
    public var serverHost: String { serverURL.host() ?? serverURL.absoluteString }

    /// Parses a `hiboss://pair?server=…&code=…` link.
    public static func parse(_ rawValue: String) -> Result<Self, PairingPayloadError> {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed) else {
            return .failure(.malformedURL)
        }
        guard components.scheme?.lowercased() == "hiboss" else {
            return .failure(.wrongScheme)
        }
        guard components.host?.lowercased() == "pair", components.path.isEmpty else {
            return .failure(.malformedURL)
        }
        let queryItems = components.queryItems ?? []
        guard queryItems.count == 2,
              let server = queryItems.first(where: { $0.name == "server" })?.value,
              let code = queryItems.first(where: { $0.name == "code" })?.value,
              !server.isEmpty, !code.isEmpty else {
            return .failure(.missingValue)
        }
        return make(server: server, code: code, defaultsToHTTPS: false)
    }

    /// Builds a payload from a typed server address and code. A bare host means https.
    public static func make(server: String, code: String) -> Result<Self, PairingPayloadError> {
        make(server: server, code: code, defaultsToHTTPS: true)
    }

    private static func make(
        server: String, code: String, defaultsToHTTPS: Bool
    ) -> Result<Self, PairingPayloadError> {
        let address = server.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, !code.isEmpty else { return .failure(.missingValue) }
        let withScheme = defaultsToHTTPS && !address.contains("://") ? "https://\(address)" : address
        guard let serverURL = URL(string: withScheme),
              let scheme = serverURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = serverURL.host(), !host.isEmpty else {
            return .failure(.invalidServerURL)
        }
        guard scheme == "https" || isLoopback(host) else { return .failure(.insecureServer) }
        guard PairingGrant.isValidCode(code) else { return .failure(.invalidCode) }
        return .success(Self(serverURL: serverURL, code: code))
    }

    /// Plain HTTP is accepted only for a server on this machine.
    static func isLoopback(_ host: String) -> Bool {
        ["localhost", "127.0.0.1"].contains(host.lowercased())
    }
}

public enum PairingPayloadError: Error, Equatable, LocalizedError, Sendable {
    case malformedURL
    case wrongScheme
    case missingValue
    case invalidServerURL
    case insecureServer
    case invalidCode

    public var errorDescription: String? {
        switch self {
        case .malformedURL, .wrongScheme:
            kitL("That is not a HiBoss pairing link.")
        case .missingValue:
            kitL("Enter both the server and the pairing code.")
        case .invalidServerURL:
            kitL("Enter a valid server URL.")
        case .insecureServer:
            kitL("The server must use HTTPS. Plain HTTP is allowed only for localhost.")
        case .invalidCode:
            kitL("That pairing code is not valid. It starts with hb_pair_.")
        }
    }
}
