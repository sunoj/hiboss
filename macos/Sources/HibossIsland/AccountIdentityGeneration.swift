// Shared macOS account-generation token for invalidating late account-scoped results.
// Exports AccountIdentityGeneration; it is owned by the main window and its stores.
// Dependencies: Foundation concurrency annotations only.

@MainActor
final class AccountIdentityGeneration {
    private(set) var value = 0

    func changed() {
        value &+= 1
    }
}
