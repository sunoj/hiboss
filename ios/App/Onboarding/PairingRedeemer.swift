// Redeems a pairing code and prepares a safe human device label.
// Exports: PairingRedeemer, PairingRedeemError, and DeviceLabel.
// Dependencies: Foundation URLSession and UIKit device metadata.

import Foundation
import UIKit

struct PairingRedeemer: Sendable {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func redeem(payload: PairingPayload, deviceLabel: String) async throws -> String {
        let endpoint = payload.serverURL
            .appendingPathComponent("api")
            .appendingPathComponent("pairing")
            .appendingPathComponent("redeem")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            PairingRedeemRequest(code: payload.code, deviceLabel: DeviceLabel.sanitize(deviceLabel))
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PairingRedeemError.invalidResponse
        }
        if httpResponse.statusCode == 400 {
            throw PairingRedeemError.invalidOrExpired
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PairingRedeemError.requestFailed
        }
        let decoded = try JSONDecoder().decode(PairingRedeemResponse.self, from: data)
        guard !decoded.token.isEmpty else { throw PairingRedeemError.invalidResponse }
        return decoded.token
    }
}

enum PairingRedeemError: Error, LocalizedError {
    case invalidOrExpired
    case requestFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidOrExpired:
            String(localized: "That pairing code is no longer valid. Scan again to try another code.")
        case .requestFailed:
            String(localized: "Couldn’t redeem the pairing code. Check your connection and try again.")
        case .invalidResponse:
            String(localized: "The server returned an invalid pairing response.")
        }
    }
}

enum DeviceLabel {
    @MainActor
    static func current() -> String {
        sanitize(UIDevice.current.name)
    }

    static func sanitize(_ raw: String) -> String {
        let forbidden = CharacterSet(charactersIn: "<>&")
        let safeScalars = raw.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && !forbidden.contains($0)
        }
        let cleaned = String(String.UnicodeScalarView(safeScalars))
        let label = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return label.isEmpty ? "iPhone" : String(label.prefix(100))
    }
}

private struct PairingRedeemRequest: Encodable {
    let code: String
    let deviceLabel: String

    enum CodingKeys: String, CodingKey {
        case code
        case deviceLabel = "device_label"
    }
}

private struct PairingRedeemResponse: Decodable {
    let token: String
}
