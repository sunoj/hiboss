// The iPhone's server address rule: App Transport Security lets the app reach only HTTPS.
// Exports: ServerAddressPolicy and ServerAddressError, the specific HTTPS message.
// Dependencies: Foundation, HibossKit PairingPayloadError.

import Foundation
import HibossKit

enum ServerAddressError: LocalizedError, Equatable {
    case requiresHTTPS

    var errorDescription: String? {
        String(localized: "The iPhone app connects only over HTTPS. Use your server's https:// address.")
    }
}

enum ServerAddressPolicy {
    /// Refuses a plain `http://` address before any request; loopback stays usable in Simulator.
    static func check(_ address: String) -> ServerAddressError? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "http" else { return nil }
        let host = url.host()?.lowercased() ?? ""
        return ["localhost", "127.0.0.1"].contains(host) ? nil : .requiresHTTPS
    }

    static func message(for error: PairingPayloadError) -> String {
        error == .insecureServer
            ? ServerAddressError.requiresHTTPS.localizedDescription : error.localizedDescription
    }

    /// An App Transport Security refusal, e.g. after a redirect to http, gets the same message.
    static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError, urlError.code == .appTransportSecurityRequiresSecureConnection {
            return ServerAddressError.requiresHTTPS.localizedDescription
        }
        return error.localizedDescription
    }
}
