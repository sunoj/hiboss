// Shared macOS account-generation token for invalidating late account-scoped results.
// Exports AccountIdentityGeneration; AppSettings owns the token shared by windows and stores.
// Dependencies: Foundation concurrency annotations only.

@MainActor
final class AccountIdentityGeneration {
    private(set) var value = 0

    func changed() {
        value &+= 1
    }
}
