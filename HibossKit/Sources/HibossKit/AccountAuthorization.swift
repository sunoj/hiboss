// Shared account boundary for rejected credentials across native reads, writes and intents.
// Exports AccountAuthorization; subscriptions synchronously discard account data on the main actor.
// Dependencies: Combine and typed HibossAPI/JoinRequest errors.

import Combine
import Foundation

@MainActor
public final class AccountAuthorization: ObservableObject {
    public static let shared = AccountAuthorization()
    @Published public private(set) var generation = 0
    private var account: ConnectionConfig?
    public private(set) var hasRejectedAccount = false
    private let rejections = PassthroughSubject<Error, Never>()

    public init() {}

    public static func isRejected(_ error: Error) -> Bool {
        (error as? HibossAPIError)?.isAuthFailure == true
            || (error as? JoinRequestError) == .forbidden
    }

    @discardableResult
    public func reject(_ error: Error) -> Bool {
        guard Self.isRejected(error) else { return false }
        hasRejectedAccount = true
        if let account {
            let prefix = "hiboss.questionnaire.\(account.serverURL.absoluteString)."
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        generation += 1
        rejections.send(error)
        return true
    }

    public func connect(_ account: ConnectionConfig?) {
        self.account = account
        hasRejectedAccount = false
    }

    public func reject(_ error: Error, account: ConnectionConfig) {
        guard account == self.account, !hasRejectedAccount, Self.isRejected(error) else { return }
        hasRejectedAccount = true
        reject(error)
    }

    public func observe(_ clear: @escaping @MainActor (Error) -> Void) -> AnyCancellable {
        rejections.sink { error in clear(error) }
    }
}
