// Contract coverage for the iOS pairing redemption request body.
// Exports: PairingRedeemerTests and ConnectionStoreTests for safe pairing restoration.
// Dependencies: XCTest, HibossKit signing contracts, and the HiBoss app target.

import Foundation
import HibossKit
import XCTest
@testable import HiBoss

final class PairingRedeemerTests: XCTestCase {
    func testRedeemRequestIncludesSigningRegistration() throws {
        let registration = PairingSigningRegistration(
            algorithm: "ES256",
            clientKind: .ios,
            publicKey: "public-key",
            proof: "pairing-proof"
        )
        let request = PairingRedeemRequest(
            code: "hb_pair_\(String(repeating: "a", count: 64))",
            deviceLabel: "Ming’s iPhone",
            signing: registration
        )

        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(CapturedPairingRequest.self, from: encoded)

        XCTAssertEqual(decoded.signing?.algorithm, "ES256")
        XCTAssertEqual(decoded.signing?.clientKind, "ios")
        XCTAssertEqual(decoded.signing?.publicKey, "public-key")
        XCTAssertEqual(decoded.signing?.proof, "pairing-proof")
    }
}

@MainActor
final class ConnectionStoreTests: XCTestCase {
    func testRestoreDoesNotExposeOrphanTokenWithoutServerURL() async throws {
        let suiteName = "ConnectionStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ConnectionStore(
            defaults: defaults,
            keychain: StubTokenStore(token: "orphan-token"),
            signerStore: StubSignerStore()
        )

        await store.restore()

        XCTAssertEqual(store.serverAddress, "")
        XCTAssertEqual(store.bossToken, "")
        XCTAssertFalse(store.isConfigured)
    }
}

private struct CapturedPairingRequest: Decodable {
    let signing: CapturedSigning?
}

private struct CapturedSigning: Decodable {
    let algorithm: String
    let clientKind: String
    let publicKey: String
    let proof: String

    enum CodingKeys: String, CodingKey {
        case algorithm
        case clientKind = "client_kind"
        case publicKey = "public_key"
        case proof
    }
}

private struct StubTokenStore: TokenStoring {
    let token: String?

    func read() throws -> String? { token }
    func write(_ token: String) throws {}
}

private struct StubSignerStore: MessageSignerStoring {
    func read() throws -> SecureEnclaveMessageSigner? { nil }
    func write(_ signer: SecureEnclaveMessageSigner) throws {}
    func delete() throws {}
}
