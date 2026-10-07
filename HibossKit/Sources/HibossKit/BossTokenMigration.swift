// Moves only the boss token after verifying the shared Keychain copy.
// Exports BossTokenMigration; failed operations preserve the private item.
// Dependencies: TokenStoring and TokenRemoving storage boundaries.

public struct BossTokenMigration: Sendable {
    private let legacy: any TokenRemoving
    private let shared: any TokenStoring

    public init(legacy: any TokenRemoving, shared: any TokenStoring) {
        self.legacy = legacy
        self.shared = shared
    }

    public func migrate() throws {
        let current = try shared.read()
        guard let old = try legacy.read(), !old.isEmpty else { return }
        if let current {
            if current == old { try legacy.delete() }
            return
        }
        try shared.write(old)
        guard try shared.read() == old else { throw SettingsError.missingToken }
        try legacy.delete()
    }
}
