// The NSE's relay-push decryption and rewrite: valid, wrong key, swapped kind, truncated, oversized.
// Exports: PushRelayCipherTests.
// Dependencies: XCTest, CryptoKit, UserNotifications, PushPayloadCipher, RelayNotificationContent.

import CryptoKit
import UserNotifications
import XCTest
@testable import HiBoss

final class PushRelayCipherTests: XCTestCase {
    private let key = Data((0..<32).map { UInt8($0) })
    private let directPayload: [String: Any] = [
        "aps": ["alert": ["title": "deploy-bot", "subtitle": "release", "body": "Ship 1.0?"],
                "category": "HIBOSS_OPTIONS", "thread-id": "agent-1", "interruption-level": "active"],
        "messageId": "m_42", "options": ["Ship", "Hold"],
    ]

    private func sealed(_ kind: PushKind = .decision, key: Data? = nil) throws -> String {
        let plaintext = try JSONSerialization.data(withJSONObject: directPayload)
        return try PushPayloadCipher.seal(plaintext, pushKey: key ?? self.key, kind: kind)
    }

    /// The generic alert exactly as the relay sends it.
    private func relayContent(_ ciphertext: String, locKey: String = "HIBOSS_PUSH_DECISION")
        -> UNMutableNotificationContent
    {
        let content = UNMutableNotificationContent()
        content.title = "HiBoss"
        content.body = "A decision is waiting for you."
        content.userInfo = ["aps": ["alert": ["title-loc-key": "HIBOSS_PUSH_TITLE", "loc-key": locKey],
                                    "mutable-content": 1], "e": ciphertext]
        return content
    }

    func testValidCiphertextRewritesLikeADirectPush() throws {
        let rewritten = try XCTUnwrap(RelayNotificationContent.rewrite(relayContent(sealed()), pushKey: key))
        XCTAssertEqual(rewritten.title, "deploy-bot")
        XCTAssertEqual(rewritten.subtitle, "release")
        XCTAssertEqual(rewritten.body, "Ship 1.0?")
        XCTAssertEqual(rewritten.categoryIdentifier, "HIBOSS_OPTIONS")
        XCTAssertEqual(rewritten.threadIdentifier, "agent-1")
        XCTAssertEqual(rewritten.userInfo["messageId"] as? String, "m_42")
        XCTAssertEqual(rewritten.userInfo["options"] as? [String], ["Ship", "Hold"])
        XCTAssertNil(rewritten.userInfo["e"], "userInfo must match the direct payload")
    }

    func testWrongKeyKeepsTheGenericAlert() throws {
        let other = Data(repeating: 7, count: 32)
        XCTAssertThrowsError(try PushPayloadCipher.open(sealed(), pushKey: other, kind: .decision)) {
            XCTAssertEqual($0 as? PushPayloadCipher.Failure, .authentication)
        }
        XCTAssertNil(RelayNotificationContent.rewrite(relayContent(try sealed()), pushKey: other))
        XCTAssertNil(RelayNotificationContent.rewrite(relayContent(try sealed()), pushKey: nil))
    }

    func testSwappedKindFailsTheAAD() throws {
        let ciphertext = try sealed(.decision)
        XCTAssertThrowsError(try PushPayloadCipher.open(ciphertext, pushKey: key, kind: .message)) {
            XCTAssertEqual($0 as? PushPayloadCipher.Failure, .authentication)
        }
        XCTAssertNil(RelayNotificationContent.rewrite(
            relayContent(ciphertext, locKey: "HIBOSS_PUSH_MESSAGE"), pushKey: key))
        XCTAssertNil(RelayNotificationContent.rewrite(relayContent(ciphertext, locKey: "OTHER"), pushKey: key))
    }

    func testTruncatedCiphertextIsRejected() throws {
        let bytes = try XCTUnwrap(Base64URL.decode(sealed()))
        let shortened = Base64URL.encode(bytes.dropLast(1))
        XCTAssertThrowsError(try PushPayloadCipher.open(shortened, pushKey: key, kind: .decision)) {
            XCTAssertEqual($0 as? PushPayloadCipher.Failure, .authentication)
        }
        let tiny = Base64URL.encode(bytes.prefix(27))
        XCTAssertThrowsError(try PushPayloadCipher.open(tiny, pushKey: key, kind: .decision)) {
            XCTAssertEqual($0 as? PushPayloadCipher.Failure, .wrongSize)
        }
        XCTAssertThrowsError(try PushPayloadCipher.open("not base64!", pushKey: key, kind: .decision)) {
            XCTAssertEqual($0 as? PushPayloadCipher.Failure, .malformed)
        }
        XCTAssertNil(RelayNotificationContent.rewrite(relayContent(shortened), pushKey: key))
    }

    func testOversizedCiphertextIsRejectedBeforeDecrypting() throws {
        let plaintext = Data(repeating: 0x61, count: PushPayloadCipher.maxCiphertextLength)
        let oversized = try PushPayloadCipher.seal(plaintext, pushKey: key, kind: .system)
        XCTAssertThrowsError(try PushPayloadCipher.open(oversized, pushKey: key, kind: .system)) {
            XCTAssertEqual($0 as? PushPayloadCipher.Failure, .wrongSize)
        }
        let limit = Data(repeating: 0x61, count: PushPayloadCipher.maxCiphertextLength - 28)
        let atLimit = try PushPayloadCipher.seal(limit, pushKey: key, kind: .system)
        XCTAssertThrowsError(try PushPayloadCipher.open(atLimit, pushKey: key, kind: .system)) {
            XCTAssertEqual($0 as? PushPayloadCipher.Failure, .notJSONObject, "2,048 bytes is accepted")
        }
    }

    /// The server encrypts with WebCrypto: nonce || ciphertext || tag, unpadded base64url.
    func testServerLayoutWithAFixedNonceOpens() throws {
        let nonce = try AES.GCM.Nonce(data: Data(repeating: 9, count: 12))
        let plaintext = Data(#"{"aps":{"alert":{"title":"t","body":"b"}}}"#.utf8)
        let box = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key), nonce: nonce,
                                   authenticating: Data("hiboss-push-v1|message".utf8))
        let wire = Base64URL.encode(Data(nonce) + box.ciphertext + box.tag)
        XCTAssertFalse(wire.contains("="))
        let opened = try PushPayloadCipher.open(wire, pushKey: key, kind: .message)
        XCTAssertEqual((opened["aps"] as? [String: Any])?.keys.sorted(), ["alert"])
    }
}
