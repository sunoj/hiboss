// Parses the Mac-to-iPhone pairing URL without exposing its credential.
// Exports: PairingPayload and PairingPayloadError.
// Dependencies: Foundation URLComponents and URL validation.

import Foundation

struct PairingPayload: Equatable, Sendable {
    let serverURL: URL
    let code: String

    static func parse(_ rawValue: String) -> Result<Self, PairingPayloadError> {
        guard let components = URLComponents(string: rawValue) else {
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
              let serverValue = queryItems.first(where: { $0.name == "server" })?.value,
              let code = queryItems.first(where: { $0.name == "code" })?.value,
              !serverValue.isEmpty else {
            return .failure(.missingValue)
        }
        guard let serverURL = URL(string: serverValue),
              let scheme = serverURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              serverURL.host != nil else {
            return .failure(.invalidServerURL)
        }
        guard isPairingCode(code) else { return .failure(.invalidCode) }
        return .success(Self(serverURL: serverURL, code: code))
    }

    private static func isPairingCode(_ code: String) -> Bool {
        let prefix = "hb_pair_"
        guard code.hasPrefix(prefix), code.count == prefix.count + 64 else { return false }
        let hexDigits = "0123456789abcdefABCDEF"
        return code.dropFirst(prefix.count).allSatisfy { hexDigits.contains($0) }
    }
}

enum PairingPayloadError: Error, Equatable, LocalizedError {
    case malformedURL
    case wrongScheme
    case missingValue
    case invalidServerURL
    case invalidCode

    var errorDescription: String? {
        String(localized: "That QR code is not a valid HiBoss pairing code.")
    }
}
