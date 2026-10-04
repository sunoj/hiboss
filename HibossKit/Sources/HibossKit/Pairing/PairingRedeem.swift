// Redeems a one-time pairing code at POST /api/pairing/redeem for a boss bearer token.
// Exports: PairingRedeeming, PairingRedeemClient, PairingRedeemRequest, PairingRedemptionGrant,
// PairingRedeemError, and DeviceLabel.
// Dependencies: Foundation URLSession; callers own credential persistence.

import Foundation

public protocol PairingRedeeming: Sendable {
    func redeem(
        payload: PairingPayload, deviceLabel: String, signing: PairingSigningRegistration?
    ) async throws -> PairingRedemptionGrant
}

public struct PairingRedeemClient: PairingRedeeming {
    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Unauthenticated: the code is the credential. Pass a label already run through
    /// `DeviceLabel.sanitize`. The returned token is never logged here.
    public func redeem(
        payload: PairingPayload, deviceLabel: String, signing: PairingSigningRegistration? = nil
    ) async throws -> PairingRedemptionGrant {
        let endpoint = payload.serverURL
            .appendingPathComponent("api")
            .appendingPathComponent("pairing")
            .appendingPathComponent("redeem")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            PairingRedeemRequest(code: payload.code, deviceLabel: deviceLabel, signing: signing)
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PairingRedeemError.invalidResponse }
        if http.statusCode == 400 { throw PairingRedeemError.invalidOrExpired }
        guard (200..<300).contains(http.statusCode) else { throw PairingRedeemError.requestFailed }
        guard let decoded = try? JSONDecoder().decode(PairingRedeemResponse.self, from: data),
              !decoded.token.isEmpty, !decoded.boss.id.isEmpty else {
            throw PairingRedeemError.invalidResponse
        }
        return PairingRedemptionGrant(
            token: decoded.token, bossID: decoded.boss.id, signingKeyID: decoded.signingKeyID
        )
    }
}

public struct PairingRedemptionGrant: Sendable {
    public let token: String
    public let bossID: String
    public let signingKeyID: String?

    public init(token: String, bossID: String, signingKeyID: String?) {
        self.token = token
        self.bossID = bossID
        self.signingKeyID = signingKeyID
    }
}

public enum PairingRedeemError: Error, Equatable, LocalizedError, Sendable {
    case invalidOrExpired
    case requestFailed
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidOrExpired:
            kitL("That pairing code is no longer valid. Ask for a fresh code and try again.")
        case .requestFailed:
            kitL("Couldn’t redeem the pairing code. Check your connection and try again.")
        case .invalidResponse:
            kitL("The server returned an invalid pairing response.")
        }
    }
}

public struct PairingRedeemRequest: Encodable, Sendable {
    public let code: String
    public let deviceLabel: String
    public let signing: PairingSigningRegistration?

    public init(code: String, deviceLabel: String, signing: PairingSigningRegistration? = nil) {
        self.code = code
        self.deviceLabel = deviceLabel
        self.signing = signing
    }

    enum CodingKeys: String, CodingKey {
        case code, signing
        case deviceLabel = "device_label"
    }
}

struct PairingRedeemResponse: Decodable {
    let token: String
    let boss: Boss
    let signingKeyID: String?

    struct Boss: Decodable {
        let id: String
    }

    enum CodingKeys: String, CodingKey {
        case token, boss
        case signingKeyID = "signing_key_id"
    }
}

public enum DeviceLabel {
    /// Fits the server contract: no control characters or `<>&`, ≤ 100 characters, never empty.
    public static func sanitize(_ raw: String, fallback: String) -> String {
        let forbidden = CharacterSet(charactersIn: "<>&")
        let safeScalars = raw.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && !forbidden.contains($0)
        }
        let cleaned = String(String.UnicodeScalarView(safeScalars))
        let label = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return label.isEmpty ? fallback : String(label.prefix(100))
    }
}
