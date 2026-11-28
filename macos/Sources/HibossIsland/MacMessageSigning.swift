// The Mac's boss-message signer: a Secure Enclave key created when the Mac pairs with a code.
// Exports MacMessageSigning (pairing key, stored signer, signed API clients) and MemorySignerStore.
// Dependencies: HibossKit signing (PendingSecureEnclaveSigner, KeychainMessageSignerStore, HibossAPI).

import Foundation
import HibossKit

enum MacMessageSigning {
    static let store = KeychainMessageSignerStore()

    /// A fresh key for a pairing; nil where the Mac has no Secure Enclave, so pairing still works unsigned.
    static func pairingKey() -> PendingSecureEnclaveSigner? {
        try? PendingSecureEnclaveSigner.create(clientKind: .macos)
    }

    private static let cacheLock = NSLock()
    /// Unset until first read: API clients are built per request, so the Keychain is read once.
    nonisolated(unsafe) private static var cached: SecureEnclaveMessageSigner??

    /// The signer bound to the current token, if this Mac paired with one.
    static func current() -> SecureEnclaveMessageSigner? {
        cacheLock.withLock {
            if let cached { return cached }
            let read = try? store.read()
            cached = .some(read)
            return read
        }
    }

    /// Keeps the stored signer in step with the token: a key bound to another token would be refused.
    /// Throws when the Keychain refuses, so a credential change never keeps a stale signer.
    static func replace(with signer: SecureEnclaveMessageSigner?, in store: any MessageSignerStoring) throws {
        if let signer { try store.write(signer) } else { try store.delete() }
        cacheLock.withLock { cached = nil }
    }

    /// Every boss write from this Mac goes through a client that signs with the stored key.
    static func api(_ config: ConnectionConfig) -> HibossAPI {
        HibossAPI(config: config, messageSigner: current())
    }
}

/// Holds a signer in memory: settings built with a test token store never touch the real key.
final class MemorySignerStore: MessageSignerStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var signer: SecureEnclaveMessageSigner?

    func read() throws -> SecureEnclaveMessageSigner? { lock.withLock { signer } }
    func write(_ signer: SecureEnclaveMessageSigner) throws { lock.withLock { self.signer = signer } }
    func delete() throws { lock.withLock { signer = nil } }
}
