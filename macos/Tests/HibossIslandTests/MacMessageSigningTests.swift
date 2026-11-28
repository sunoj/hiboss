// The Mac's stored signer follows its token: a new or typed token clears a key bound to another one.
// Exports MacMessageSigningTests. Dependencies: XCTest, HibossKit signer types, HibossIsland settings.

import Foundation
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class MacMessageSigningTests: XCTestCase {
    func testAdoptingAPairingGrantClearsASignerBoundToTheOldToken() throws {
        let store = MemorySignerStore()
        try store.write(try Self.signer())
        let settings = AppSettings(defaults: try Self.defaults(), keychain: SigningTokens(), signerStore: store)
        let grant = PairingRedemptionGrant(token: "hb_boss_new", bossID: "boss-1", signingKeyID: nil)

        _ = try settings.adopt(grant, server: URL(string: "https://hiboss.example")!)

        XCTAssertNil(try store.read(), "the old key is bound to another token and would be refused")
    }

    func testActivatingADeviceTokenClearsTheSigner() throws {
        let store = MemorySignerStore()
        let settings = AppSettings(defaults: try Self.defaults(), keychain: SigningTokens(), signerStore: store)
        let current = try settings.adopt(PairingRedemptionGrant(token: "hb_a", bossID: "boss-1", signingKeyID: nil),
                                         server: URL(string: "https://hiboss.example")!)
        try store.write(try Self.signer())

        _ = try settings.activateDeviceToken("hb_b", replacing: current)

        XCTAssertNil(try store.read())
    }

    private static func defaults() throws -> UserDefaults {
        let suite = "MacMessageSigningTests.\(UUID().uuidString)"
        return try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    /// A stored signer as the Keychain holds it; its key bytes are never used here.
    private static func signer() throws -> SecureEnclaveMessageSigner {
        let json = #"{"keyRepresentation":"AAAA","keyID":"key-1","bossID":"boss-1","clientKind":"macos"}"#
        return try JSONDecoder().decode(SecureEnclaveMessageSigner.self, from: Data(json.utf8))
    }
}

private final class SigningTokens: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    func read() throws -> String? { lock.withLock { token } }
    func write(_ token: String) throws { lock.withLock { self.token = token } }
}
