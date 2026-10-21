// Holds a tapped `hiboss://pair` link until the connect screen shows it for confirmation.
// Exports: PairingLinkInbox; other `hiboss://` links only open the app.
// Dependencies: Foundation, Combine, HibossKit PairingPayload.

import Combine
import Foundation
import HibossKit

@MainActor
final class PairingLinkInbox: ObservableObject {
    static let shared = PairingLinkInbox()

    /// A parsed link waiting for the boss to confirm it; never redeemed without a tap.
    @Published private(set) var pending: PairingPayload?

    func receive(_ url: URL) {
        guard url.scheme?.lowercased() == "hiboss", url.host()?.lowercased() == "pair",
              case let .success(payload) = PairingPayload.parse(url.absoluteString) else { return }
        pending = payload
    }

    /// Hands the pending link to the connect screen exactly once.
    func take() -> PairingPayload? {
        defer { pending = nil }
        return pending
    }

    /// A signed-in phone ignores a pairing link rather than keeping it for a later sign-out.
    func discard() { pending = nil }
}
