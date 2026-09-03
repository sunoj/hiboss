// Tests deterministic JWS construction independently from Secure Enclave hardware.
// Covers payload binding and ES256 verification with a software P-256 test key.
// Depends on CryptoKit and HibossKit message-signing contracts.

import CryptoKit
import Foundation
import Testing
@testable import HibossKit

struct MessageSigningTests {
    @Test func signedReplyBindsBodyBossAndParent() throws {
        let provider = SoftwareSignatureProvider()
        let messageID = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
        let compact = try BossMessageJWS.signedReply(
            body: "Approve",
            parentMessageID: "parent-1",
            provider: provider,
            issuedAt: Date(timeIntervalSince1970: 1_788_454_800),
            messageID: messageID
        )
        let segments = compact.split(separator: ".").map(String.init)
        #expect(segments.count == 3)
        let payloadData = try #require(Data(base64URLEncoded: segments[1]))
        let payload = try #require(
            JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        )
        #expect(payload["body"] as? String == "Approve")
        #expect(payload["boss_id"] as? String == "boss-1")
        let action = try #require(payload["action"] as? [String: Any])
        #expect(action["message_id"] as? String == "parent-1")

        let input = Data("\(segments[0]).\(segments[1])".utf8)
        let signatureData = try #require(Data(base64URLEncoded: segments[2]))
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)
        #expect(provider.key.publicKey.isValidSignature(signature, for: input))
    }
}

private struct SoftwareSignatureProvider: BossMessageSignatureProvider {
    let key = P256.Signing.PrivateKey()
    let keyID = "test-key"
    let bossID = "boss-1"

    func signature(for data: Data) throws -> Data {
        try key.signature(for: data).rawRepresentation
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
