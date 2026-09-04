// Shared device-pairing response and the authenticated pairing-code request.
// Exports: pairing grants/status plus HibossAPI pairing request and status methods.
// Dependencies: Foundation Codable and HibossAPI's authenticated request helpers.

import Foundation

public enum PairingGrantError: Error, Equatable, Sendable {
    case invalidCode
}

public enum PairingStatus: Equatable, Sendable {
    case pending
    case paired(deviceLabel: String)
    case expired
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

    public func pairingStatus(code: String) async throws -> PairingStatus {
        guard PairingGrant.isValidCode(code) else { throw PairingGrantError.invalidCode }
        let endpoint = config.serverURL
            .appendingPathComponent("api")
            .appendingPathComponent("boss")
            .appendingPathComponent("pairing")
            .appendingPathComponent("status")
        var request = authorizedRequest(url: endpoint, method: "POST")
        request.httpBody = try JSONEncoder().encode(PairingStatusRequest(code: code))
        let (data, response) = try await session.data(for: request)
        try validate(response)
        do {
            return try decoder.decode(PairingStatusResponse.self, from: data).status
        } catch {
            throw HibossAPIError.decodingFailed(context: "pairing status", body: "<unreadable>")
        }
    }
}

private struct PairingStatusRequest: Encodable {
    let code: String
}

private struct PairingStatusResponse: Decodable {
    let status: PairingStatus

    private enum CodingKeys: String, CodingKey {
        case status
        case deviceLabel = "device_label"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(String.self, forKey: .status) {
        case "pending": status = .pending
        case "expired": status = .expired
        case "paired":
            status = .paired(deviceLabel: try values.decode(String.self, forKey: .deviceLabel))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .status, in: values, debugDescription: "Unknown pairing status"
            )
        }
    }
}
