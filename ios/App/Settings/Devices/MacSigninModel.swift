// Review-and-approve state for signing a Mac in from this iPhone (docs/signin-with-iphone.md).
// Exports: MacSigninModel, MacSigninPhase, MacSigninCode, MacSigninFailure, SigninApproving.
// Dependencies: Foundation, HibossKit SigninLink and the HibossAPI sign-in calls.

import Foundation
import HibossKit

/// The boss-side sign-in calls, so the model can be driven without a server.
protocol SigninApproving: Sendable {
    func signinRequest(id: String) async throws -> SigninRequestSummary
    func approveSignin(id: String) async throws -> SigninApproval
    func rejectSignin(id: String) async throws
}

extension HibossAPI: SigninApproving {}

/// The approval code, held in memory only until the boss taps Done or it expires.
struct MacSigninCode: Equatable {
    let code: String
    let deviceLabel: String
    let expiresAt: Date?

    func isExpired(at now: Date) -> Bool {
        guard let expiresAt else { return false }
        return !PairingValidity.isValid(expiresAt: expiresAt, now: now)
    }
}

enum MacSigninFailure: Equatable {
    case notConfigured, forbidden, alreadyHandled, notFound, unreachable

    var message: String {
        switch self {
        case .notConfigured: String(localized: "Connect to a server before signing in a Mac.")
        case .forbidden: String(localized: "Only an admin or manager can sign in a Mac.")
        case .alreadyHandled: String(localized: "This request was already handled.")
        case .notFound:
            String(localized: "This sign-in request no longer exists. Start again on the Mac.")
        case .unreachable:
            String(localized: "Couldn’t reach your server. Check the connection and try again.")
        }
    }

    init(_ error: Error) {
        guard case let HibossAPIError.requestFailed(status, _) = error else {
            self = .unreachable
            return
        }
        switch status {
        case 403: self = .forbidden
        case 404: self = .notFound
        case 409: self = .alreadyHandled
        default: self = .unreachable
        }
    }
}

enum MacSigninPhase: Equatable {
    case idle
    case loading
    case review(SigninRequestSummary)
    case approved(MacSigninCode)
    case rejected(deviceLabel: String)
    case failed(MacSigninFailure)
}

@MainActor
final class MacSigninModel: ObservableObject {
    @Published private(set) var phase: MacSigninPhase = .idle
    /// Why the last scanned code was refused; shown under the scan button after the camera closes.
    @Published private(set) var scanRejection: String?
    @Published private(set) var isDeciding = false
    private(set) var link: SigninLink?

    private let serverURL: URL?
    private let api: (any SigninApproving)?

    init(serverURL: URL?, api: (any SigninApproving)?) {
        self.serverURL = serverURL
        self.api = api
    }

    /// Accepts a scanned `hiboss://signin` link only for the server this iPhone is signed in to.
    func accept(scanned rawValue: String) -> QRScanOutcome {
        guard phase == .idle else { return .accepted }
        guard case let .success(scanned) = SigninLink.parse(rawValue) else {
            return refuse(String(localized: "That QR code is not a HiBoss sign-in code."))
        }
        guard let serverURL, api != nil else {
            phase = .failed(.notConfigured)
            return .accepted
        }
        guard Self.isSameServer(scanned.serverURL, serverURL) else {
            return refuse(String(localized:
                "This Mac is signing in to a different server: \(scanned.serverHost)"))
        }
        link = scanned
        scanRejection = nil
        phase = .loading
        return .accepted
    }

    func load() async {
        guard phase == .loading, let link, let api else { return }
        do {
            phase = .review(try await api.signinRequest(id: link.requestID))
        } catch {
            phase = .failed(MacSigninFailure(error))
        }
    }

    func approve() async {
        guard case let .review(summary) = phase, !isDeciding, let api else { return }
        isDeciding = true
        defer { isDeciding = false }
        do {
            let approval = try await api.approveSignin(id: summary.requestID)
            phase = .approved(MacSigninCode(
                code: approval.code,
                deviceLabel: approval.deviceLabel ?? summary.deviceLabel,
                expiresAt: ISODate.parse(approval.expiresAt ?? summary.expiresAt)
            ))
        } catch {
            phase = .failed(MacSigninFailure(error))
        }
    }

    func reject() async {
        guard case let .review(summary) = phase, !isDeciding, let api else { return }
        isDeciding = true
        defer { isDeciding = false }
        do {
            try await api.rejectSignin(id: summary.requestID)
            phase = .rejected(deviceLabel: summary.deviceLabel)
        } catch {
            phase = .failed(MacSigninFailure(error))
        }
    }

    /// Back to scanning; drops the request and any code it held.
    func reset() {
        phase = .idle
        link = nil
        isDeciding = false
    }

    /// A pending request whose expiry has passed reads as expired before the server sweeps it.
    static func status(of summary: SigninRequestSummary, at now: Date) -> SigninProgress {
        guard summary.status == .pending, let expiry = ISODate.parse(summary.expiresAt),
              !PairingValidity.isValid(expiresAt: expiry, now: now) else { return summary.status }
        return .expired
    }

    /// Same scheme, host and port; a trailing slash in the path does not matter.
    static func isSameServer(_ lhs: URL, _ rhs: URL) -> Bool {
        func key(_ url: URL) -> String? {
            guard let scheme = url.scheme?.lowercased(),
                  let host = url.host()?.lowercased() else { return nil }
            let port = url.port ?? (scheme == "https" ? 443 : scheme == "http" ? 80 : -1)
            var path = url.path()
            while path.hasSuffix("/") { path.removeLast() }
            return "\(scheme)://\(host):\(port)\(path)"
        }
        guard let left = key(lhs) else { return false }
        return left == key(rhs)
    }

    private func refuse(_ message: String) -> QRScanOutcome {
        scanRejection = message
        return .rejected(message)
    }
}
