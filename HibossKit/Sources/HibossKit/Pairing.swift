// Shared device-pairing response and the authenticated pairing-code request.
// Exports: PairingGrant, PairingGrantError, and HibossAPI.requestPairingCode().
// Dependencies: Foundation Codable and HibossAPI's authenticated request helpers.

import Foundation

public enum PairingGrantError: Error, Equatable, Sendable {
    case invalidCode
}

public struct PairingGrant: Decodable, Equatable, Sendable {
    public let code: String
    public let expiresAt: Date

    public init(code: String, expiresAt: Date) throws {
        guard Self.isValidCode(code) else { throw PairingGrantError.invalidCode }
        self.code = code
        self.expiresAt = expiresAt
    }

    public static func isValidCode(_ code: String) -> Bool {
        let prefix = "hb_pair_"
        guard code.hasPrefix(prefix), code.utf8.count == prefix.utf8.count + 64 else { return false }
        return code.dropFirst(prefix.count).utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let code = try values.decode(String.self, forKey: .code)
        let rawExpiration = try values.decode(String.self, forKey: .expiresAt)
        guard let expiration = try? Date(rawExpiration, strategy: .iso8601) else {
            throw DecodingError.dataCorruptedError(
                forKey: .expiresAt,
                in: values,
                debugDescription: "Invalid pairing expiration"
            )
        }
        do {
            try self.init(code: code, expiresAt: expiration)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .code,
                in: values,
                debugDescription: "Invalid pairing code"
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case expiresAt = "expires_at"
    }
}

extension HibossAPI {
    public func requestPairingCode() async throws -> PairingGrant {
        let endpoint = config.serverURL
            .appendingPathComponent("api")
            .appendingPathComponent("boss")
            .appendingPathComponent("pairing")
        let request = authorizedRequest(url: endpoint, method: "POST")
        let (data, response) = try await session.data(for: request)
        try validate(response)
        do {
            return try decoder.decode(PairingGrant.self, from: data)
        } catch {
            throw HibossAPIError.decodingFailed(context: "pairing response", body: "<unreadable>")
        }
    }
}
