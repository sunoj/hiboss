// Issues a pairing code for another device and observes its redemption by polling status.
// Exports: PairingIssuing and DevicePairingModel, shared by the macOS sheet and iOS settings.
// Dependencies: Combine ObservableObject, HibossAPI pairing routes, and pairing presentation types.

import Combine
import CoreGraphics
import Foundation

public protocol PairingIssuing: Sendable {
    func requestPairingCode() async throws -> PairingGrant
    func pairingStatus(code: String) async throws -> PairingStatus
}

extension HibossAPI: PairingIssuing {}

@MainActor
public final class DevicePairingModel: ObservableObject {
    @Published public private(set) var grant: PairingGrant?
    @Published public private(set) var isRequesting = false
    @Published public private(set) var requestFailure: PairingRequestFailure?
    @Published public private(set) var failureMessage: String?
    @Published public private(set) var pairedDeviceLabel: String?
    @Published public private(set) var linkResult: Result<PairingLink, PairingLinkError>?
    @Published public private(set) var qrImage: CGImage?

    private let serverURL: URL?
    private let issuer: (any PairingIssuing)?
    private let pollInterval: Duration

    public convenience init(config: ConnectionConfig?) {
        self.init(serverURL: config?.serverURL, issuer: config.map { HibossAPI(config: $0) })
    }

    public init(serverURL: URL?, issuer: (any PairingIssuing)?, pollInterval: Duration = .seconds(1)) {
        self.serverURL = serverURL
        self.issuer = issuer
        self.pollInterval = pollInterval
    }

    public func state(at now: Date) -> PairingContentState {
        PairingContentState.derive(
            grant: grant,
            hasConfiguredServer: serverURL != nil && issuer != nil,
            now: now,
            isRequesting: isRequesting,
            requestFailure: requestFailure,
            linkResult: linkResult,
            canRenderQRCode: qrImage != nil,
            pairedDeviceLabel: pairedDeviceLabel
        )
    }

    public func requestCode() async {
        guard !isRequesting, let issuer, let serverURL else { return }
        isRequesting = true
        grant = nil
        linkResult = nil
        qrImage = nil
        pairedDeviceLabel = nil
        requestFailure = nil
        failureMessage = nil
        defer { isRequesting = false }
        do {
            let issued = try await issuer.requestPairingCode()
            let link = Result { try PairingLink(serverURL: serverURL, code: issued.code) }
                .mapError { $0 as? PairingLinkError ?? .invalidServerURL }
            grant = issued
            linkResult = link
            qrImage = (try? link.get()).flatMap(PairingQRCode.cgImage(for:))
        } catch {
            let failure = PairingRequestFailure.from(error)
            requestFailure = failure
            failureMessage = failure == .permissionDenied ? nil : error.localizedDescription
        }
    }

    /// Polls until the code is redeemed, expires, or the caller's task is cancelled.
    public func monitorRedemption() async {
        guard let grant, let issuer else { return }
        while !Task.isCancelled && PairingValidity.isValid(expiresAt: grant.expiresAt, now: .now) {
            do {
                switch try await issuer.pairingStatus(code: grant.code) {
                case let .paired(deviceLabel):
                    pairedDeviceLabel = deviceLabel
                    return
                case .expired:
                    return
                case .pending:
                    break
                }
            } catch {
                // Polling is advisory; the visible code stays usable through transient failures.
            }
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                return
            }
        }
    }
}
