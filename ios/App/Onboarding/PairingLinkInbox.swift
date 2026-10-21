// Holds a tapped `hiboss://pair` link until the connect screen shows it for confirmation.
// Exports: PairingLinkInbox; other `hiboss://` links only open the app.
// Dependencies: Foundation, Combine, HibossKit PairingPayload, ServerAddressPolicy.

import Combine
import Foundation
import HibossKit

@MainActor
final class PairingLinkInbox: ObservableObject {
    static let shared = PairingLinkInbox()

    /// A parsed link waiting for the boss to confirm it; never redeemed without a tap.
    @Published private(set) var pending: PairingPayload?
    /// Why the last tapped pairing link was refused, e.g. a plain `http://` server.
    @Published private(set) var refusal: String?

    func receive(_ url: URL) {
        guard url.scheme?.lowercased() == "hiboss", url.host()?.lowercased() == "pair" else { return }
        switch PairingPayload.parse(url.absoluteString) {
        case let .success(payload):
            pending = payload
            refusal = nil
        case let .failure(failure):
            refusal = ServerAddressPolicy.message(for: failure)
        }
    }

    /// Hands the pending link to the connect screen exactly once.
    func take() -> PairingPayload? {
        defer { pending = nil }
        return pending
    }

    /// Hands the refusal to the connect screen exactly once.
    func takeRefusal() -> String? {
        defer { refusal = nil }
        return refusal
    }

    /// A signed-in phone ignores a pairing link rather than keeping it for a later sign-out.
    func discard() {
        pending = nil
        refusal = nil
    }
}
