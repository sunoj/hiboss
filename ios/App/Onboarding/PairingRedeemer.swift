// Redeems a pairing code with a fresh Secure Enclave signing key bound to this iPhone.
// Exports: PairingRedeemer, PairingRedemption, and DeviceLabel.current().
// Dependencies: HibossKit PairingRedeemClient and signing contracts, UIKit device metadata.

import Foundation
import HibossKit
import UIKit

struct PairingRedeemer: Sendable {
    let client: PairingRedeemClient

    init(client: PairingRedeemClient = PairingRedeemClient()) {
        self.client = client
    }

    func redeem(payload: PairingPayload, deviceLabel: String) async throws -> PairingRedemption {
        let pendingSigner = try PendingSecureEnclaveSigner.create(clientKind: .ios)
        let grant = try await client.redeem(
            payload: payload,
            deviceLabel: DeviceLabel.sanitize(deviceLabel, fallback: "iPhone"), // i18n-exempt: fallback device name sent to the server
            signing: try pendingSigner.registration(pairingCode: payload.code)
        )
        guard let signingKeyID = grant.signingKeyID, !signingKeyID.isEmpty else {
            throw PairingRedeemError.invalidResponse
        }
        return PairingRedemption(
            token: grant.token,
            signer: pendingSigner.bind(bossID: grant.bossID, keyID: signingKeyID)
        )
    }
}

struct PairingRedemption: Sendable {
    let token: String
    let signer: SecureEnclaveMessageSigner
}

extension DeviceLabel {
    @MainActor
    static func current() -> String {
        sanitize(UIDevice.current.name, fallback: "iPhone") // i18n-exempt: fallback device name sent to the server
    }
}
