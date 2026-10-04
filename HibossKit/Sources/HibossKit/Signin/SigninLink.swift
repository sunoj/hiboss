// The hiboss://signin?server=…&request=… link a signed-out Mac shows as a QR code and a
// signed-in iPhone scans to approve that Mac's sign-in request.
// Exports: SigninLink and SigninLinkError. Dependencies: Foundation, PairingPayload.isLoopback.

import Foundation

public struct SigninLink: Equatable, Sendable {
    public let serverURL: URL
    public let requestID: String

    public var serverHost: String { serverURL.host() ?? serverURL.absoluteString }

    public init?(serverURL: URL, requestID: String) {
        guard Self.isValidRequestID(requestID), Self.isAcceptableServer(serverURL) else { return nil }
        self.serverURL = serverURL
        self.requestID = requestID
    }

    /// The link to encode in the QR code.
    public var url: URL? {
        var components = URLComponents()
        components.scheme = "hiboss"
        components.host = "signin"
        components.queryItems = [
            URLQueryItem(name: "server", value: serverURL.absoluteString),
            URLQueryItem(name: "request", value: requestID),
        ]
        return components.url
    }

    public static func parse(_ rawValue: String) -> Result<Self, SigninLinkError> {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "hiboss" else { return .failure(.notASigninLink) }
        guard components.host?.lowercased() == "signin", components.path.isEmpty else {
            return .failure(.notASigninLink)
        }
        let items = components.queryItems ?? []
        guard items.count == 2,
              let server = items.first(where: { $0.name == "server" })?.value,
              let request = items.first(where: { $0.name == "request" })?.value,
              let serverURL = URL(string: server) else { return .failure(.malformed) }
        guard isAcceptableServer(serverURL) else { return .failure(.insecureServer) }
        guard let link = Self(serverURL: serverURL, requestID: request) else { return .failure(.malformed) }
        return .success(link)
    }

    /// 32 lowercase hex characters, the shape the server issues.
    public static func isValidRequestID(_ value: String) -> Bool {
        value.count == 32 && value.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    /// HTTPS, or plain HTTP only for a server on this machine.
    static func isAcceptableServer(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host(), !host.isEmpty else { return false }
        return scheme == "https" || (scheme == "http" && PairingPayload.isLoopback(host))
    }
}

public enum SigninLinkError: Error, Equatable, Sendable {
    case notASigninLink
    case malformed
    case insecureServer
}
