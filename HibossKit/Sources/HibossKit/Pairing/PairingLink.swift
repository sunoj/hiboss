// Builds the hiboss://pair link an issuing device shows, its QR image, and its countdown.
// Exports: PairingLink, PairingLinkError, PairingValidity, and PairingQRCode.
// Dependencies: Foundation, CoreImage, and PairingPayload for the round-trip check.

import CoreImage
import Foundation

public enum PairingLinkError: Error, Equatable, Sendable {
    case invalidCode
    case invalidServerURL
}

/// Carries only the server and the one-time pairing code — never a bearer token.
public struct PairingLink: Equatable, Sendable {
    public let url: URL

    public init(serverURL: URL, code: String) throws {
        guard PairingGrant.isValidCode(code) else { throw PairingLinkError.invalidCode }
        let allowedCharacters = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        )
        guard let encodedServer = serverURL.absoluteString.addingPercentEncoding(
            withAllowedCharacters: allowedCharacters
        ), let url = URL(string: "hiboss://pair?server=\(encodedServer)&code=\(code)") else {
            throw PairingLinkError.invalidServerURL
        }
        // A link the receiving device would refuse (for example plain HTTP on a LAN) is not offered.
        guard case .success = PairingPayload.parse(url.absoluteString) else {
            throw PairingLinkError.invalidServerURL
        }
        self.url = url
    }
}

public enum PairingValidity {
    public static func isValid(expiresAt: Date, now: Date) -> Bool {
        expiresAt > now
    }

    public static func remainingSeconds(expiresAt: Date, now: Date) -> Int {
        max(0, Int(ceil(expiresAt.timeIntervalSince(now))))
    }

    /// m:ss countdown in the locale's digits and separators.
    public static func formatted(remainingSeconds: Int, locale: Locale = .autoupdatingCurrent) -> String {
        Duration.seconds(max(0, remainingSeconds))
            .formatted(.time(pattern: .minuteSecond).locale(locale))
    }
}

public enum PairingQRCode {
    /// Renders the link as a crisp QR bitmap; nil when CoreImage cannot produce one.
    public static func cgImage(for link: PairingLink) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(link.url.absoluteString.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(
            by: CGAffineTransform(scaleX: 12, y: 12)
        ) else { return nil }
        return CIContext(options: [.useSoftwareRenderer: true]).createCGImage(output, from: output.extent)
    }
}
