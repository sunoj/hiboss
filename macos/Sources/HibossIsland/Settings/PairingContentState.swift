// Pure state derivation for the device-pairing sheet.
// Exports: PairingRequestFailure and PairingContentState.
// Dependencies: Foundation, HibossKit pairing errors, PairingLink, and PairingValidity.

import Foundation
import HibossKit

enum PairingRequestFailure: Equatable {
    case permissionDenied
    case failed

    static func from(_ error: Error) -> Self {
        guard let apiError = error as? HibossAPIError,
              case .requestFailed(status: 403, message: _) = apiError else {
            return .failed
        }
        return .permissionDenied
    }
}

enum PairingContentState: Equatable {
    case requesting
    case notConfigured
    case noCode
    case expired
    case permissionDenied
    case requestFailed
    case invalidLink
    case qrUnavailable
    case ready(grant: PairingGrant, link: PairingLink)

    static func derive(
        grant: PairingGrant?,
        hasConfiguredServer: Bool,
        now: Date,
        isRequesting: Bool,
        requestFailure: PairingRequestFailure?,
        linkResult: Result<PairingLink, PairingLinkError>?,
        canRenderQRCode: Bool
    ) -> Self {
        if isRequesting { return .requesting }
        switch requestFailure {
        case .permissionDenied: return .permissionDenied
        case .failed: return .requestFailed
        case nil: break
        }
        guard hasConfiguredServer else { return .notConfigured }
        guard let grant else { return .noCode }
        guard PairingValidity.isValid(expiresAt: grant.expiresAt, now: now) else { return .expired }
        guard case let .success(link) = linkResult else { return .invalidLink }
        guard canRenderQRCode else { return .qrUnavailable }
        return .ready(grant: grant, link: link)
    }
}
