// Shared account identity and rejection boundary across native reads, writes and intents.
// Exports AccountAuthorization; generation and subscriptions invalidate account-scoped work.
// Dependencies: Combine and typed HibossAPI/JoinRequest errors.

import Combine
import Foundation

@MainActor
public final class AccountAuthorization: ObservableObject {
    public static let shared = AccountAuthorization()
    @Published public private(set) var generation = 0
    private var account: ConnectionConfig?
    public private(set) var hasRejectedAccount = false
    private let changes = PassthroughSubject<Error, Never>()

    public init() {}

    public static func isRejected(_ error: Error) -> Bool {
        (error as? HibossAPIError)?.isAuthFailure == true
            || (error as? JoinRequestError) == .forbidden
    }

    @discardableResult
    public func reject(_ error: Error) -> Bool {
        guard Self.isRejected(error) else { return false }
        hasRejectedAccount = true
        clearDrafts(for: account)
        generation &+= 1
        changes.send(error)
        return true
    }

    public func connect(_ account: ConnectionConfig?) {
        let didChange = self.account != account
        if didChange { clearDrafts(for: self.account) }
        self.account = account
        hasRejectedAccount = false
        if didChange { changed() }
    }

    public func disconnect() {
        if hasRejectedAccount { account = nil } else { connect(nil) }
    }

    public func changed() {
        generation &+= 1
        changes.send(CancellationError())
    }

    public func reject(_ error: Error, account: ConnectionConfig) {
        guard account == self.account, !hasRejectedAccount, Self.isRejected(error) else { return }
        hasRejectedAccount = true
        reject(error)
    }

    private func clearDrafts(for account: ConnectionConfig?) {
        if let account {
            let prefix = "hiboss.questionnaire.\(account.serverURL.absoluteString)."
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    public func observe(_ clear: @escaping @MainActor (Error) -> Void) -> AnyCancellable {
        changes.sink { error in clear(error) }
    }
}
