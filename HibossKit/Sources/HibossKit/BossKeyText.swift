// What an agent machine pins: the fingerprint the app shows and the key text `hiboss boss trust` reads.
// Exports SecureEnclaveMessageSigner.fingerprint and keyText(label:); the CLI's boss_key_text.rs
// parses the same `hiboss-boss-key:` + base64url(JSON) format.
// Dependencies: CryptoKit Secure Enclave keys, Foundation JSON.

import CryptoKit
import Foundation

extension SecureEnclaveMessageSigner {
    /// `xxxx-xxxx-xxxx-xxxx`: the first 16 characters of the key id, as `hiboss boss keys` prints it.
    public var fingerprint: String {
        let head = Array(keyID.prefix(16))
        return stride(from: 0, to: head.count, by: 4)
            .map { String(head[$0..<min($0 + 4, head.count)]) }.joined(separator: "-")
    }

    /// The text an agent machine pins with `hiboss boss trust`.
    public func keyText(label: String?) throws -> String {
        let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: keyRepresentation)
        var fields: [String: String] = [
            "boss_id": bossID, "key_id": keyID, "client_kind": clientKind.rawValue,
            "public_key": key.publicKey.x963Representation.base64URLEncodedString(),
        ]
        if let label, !label.isEmpty { fields["label"] = label }
        let json = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        return "hiboss-boss-key:" + json.base64URLEncodedString()
    }
}
