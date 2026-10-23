// Opens a relay push: `e` = base64url(nonce(12) || AES-256-GCM ciphertext || tag).
// Exports: PushKind, PushPayloadCipher and Base64URL.
// Dependencies: CryptoKit and Foundation.

import CryptoKit
import Foundation

/// The relay picks only the generic loc-key from the kind; the AAD binds it to the content.
/// `resolved` is a silent background push with no alert, so it has no loc-key.
enum PushKind: String, CaseIterable, Sendable {
    case decision, message, system, resolved

    var locKey: String? {
        switch self {
        case .decision: "HIBOSS_PUSH_DECISION"
        case .message: "HIBOSS_PUSH_MESSAGE"
        case .system: "HIBOSS_PUSH_SYSTEM"
        case .resolved: nil
        }
    }

    init?(locKey: String) {
        guard let kind = Self.allCases.first(where: { $0.locKey == locKey }) else { return nil }
        self = kind
    }

    var additionalData: Data { Data("hiboss-push-v1|\(rawValue)".utf8) }
}

enum PushPayloadCipher {
    static let nonceLength = 12
    static let tagLength = 16
    static let maxCiphertextLength = 2_048

    enum Failure: Error, Equatable {
        case malformed, wrongSize, authentication, notJSONObject
    }

    /// Returns the plaintext userInfo dictionary, or throws without revealing which byte failed.
    static func open(_ encoded: String, pushKey: Data, kind: PushKind) throws -> [String: Any] {
        guard pushKey.count == 32, let combined = Base64URL.decode(encoded) else { throw Failure.malformed }
        guard combined.count >= nonceLength + tagLength, combined.count <= maxCiphertextLength else {
            throw Failure.wrongSize
        }
        let plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            plaintext = try AES.GCM.open(box, using: SymmetricKey(data: pushKey),
                                         authenticating: kind.additionalData)
        } catch {
            throw Failure.authentication
        }
        guard let object = try? JSONSerialization.jsonObject(with: plaintext) as? [String: Any] else {
            throw Failure.notJSONObject
        }
        return object
    }

    /// Seals like the server does; the app only uses it in tests.
    static func seal(_ plaintext: Data, pushKey: Data, kind: PushKind) throws -> String {
        let box = try AES.GCM.seal(plaintext, using: SymmetricKey(data: pushKey),
                                   authenticating: kind.additionalData)
        guard let combined = box.combined else { throw Failure.malformed }
        return Base64URL.encode(combined)
    }
}

enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ value: String) -> Data? {
        guard value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { return nil }
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}
