// Pure presentation state for a device that issues a pairing code and watches it redeem.
// Exports: PairingContentState and PairingRequestFailure with its role-denied copy.
// Dependencies: Foundation, HibossAPIError, PairingGrant, PairingLink, and PairingValidity.

import Foundation

public enum PairingRequestFailure: Equatable, Sendable {
    case permissionDenied
    case failed

    /// A 403 from the issue route means this boss's role may not create pairing codes.
    public static func from(_ error: Error) -> Self {
        guard let apiError = error as? HibossAPIError,
              case .requestFailed(status: 403, message: _) = apiError else {
            return .failed
        }
        return .permissionDenied
    }

    public var title: String {
        switch self {
        case .permissionDenied: kitL("Your role cannot pair devices")
        case .failed: kitL("Couldn’t request a pairing code")
        }
    }

    public var detail: String {
        switch self {
        case .permissionDenied: kitL("Ask an administrator or manager to pair this device.")
        case .failed: kitL("Try again when the server is reachable.")
        }
    }
}

public enum PairingContentState: Equatable, Sendable {
    case requesting
    case paired(deviceLabel: String)
    case notConfigured
    case noCode
    case expired
    case permissionDenied
    case requestFailed
    case invalidLink
    case qrUnavailable
    case ready(grant: PairingGrant, link: PairingLink)

    public static func derive(
        grant: PairingGrant?,
        hasConfiguredServer: Bool,
        now: Date,
        isRequesting: Bool,
        requestFailure: PairingRequestFailure?,
        linkResult: Result<PairingLink, PairingLinkError>?,
        canRenderQRCode: Bool,
        pairedDeviceLabel: String? = nil
    ) -> Self {
        if isRequesting { return .requesting }
        switch requestFailure {
        case .permissionDenied: return .permissionDenied
        case .failed: return .requestFailed
        case nil: break
        }
        guard hasConfiguredServer else { return .notConfigured }
        if let pairedDeviceLabel { return .paired(deviceLabel: pairedDeviceLabel) }
        guard let grant else { return .noCode }
        guard PairingValidity.isValid(expiresAt: grant.expiresAt, now: now) else { return .expired }
        guard case let .success(link) = linkResult else { return .invalidLink }
        guard canRenderQRCode else { return .qrUnavailable }
        return .ready(grant: grant, link: link)
    }
}
