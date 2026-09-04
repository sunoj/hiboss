// Pure state, link, validity, and QR helpers for the device-pairing sheet.
// Exports pairing presentation types consumed by DevicePairingSheet and tests.
// Dependencies: Foundation, AppKit/CoreImage, and HibossKit pairing contracts.

import AppKit
import CoreImage
import Foundation
import HibossKit

enum PairingLinkError: Error, Equatable {
    case invalidCode
    case invalidServerURL
}

struct PairingLink: Equatable, Sendable {
    let url: URL

    init(serverURL: URL, code: String) throws {
        guard PairingGrant.isValidCode(code) else { throw PairingLinkError.invalidCode }
        let allowedCharacters = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        )
        guard let encodedServer = serverURL.absoluteString.addingPercentEncoding(
            withAllowedCharacters: allowedCharacters
        ), let url = URL(string: "hiboss://pair?server=\(encodedServer)&code=\(code)") else {
            throw PairingLinkError.invalidServerURL
        }
        self.url = url
    }
}

enum PairingValidity {
    static func isValid(expiresAt: Date, now: Date) -> Bool {
        expiresAt > now
    }

    static func remainingSeconds(expiresAt: Date, now: Date) -> Int {
        max(0, Int(ceil(expiresAt.timeIntervalSince(now))))
    }

    static func formatted(remainingSeconds: Int) -> String {
        let minutes = max(0, remainingSeconds) / 60
        let seconds = max(0, remainingSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

enum PairingQRCodeGenerator {
    static func image(for link: PairingLink) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(link.url.absoluteString.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(
            by: CGAffineTransform(scaleX: 12, y: 12)
        ) else { return nil }
        let representation = NSCIImageRep(ciImage: output)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}

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
    case paired(deviceLabel: String)
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
