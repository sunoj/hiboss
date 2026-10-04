// The signed-out Mac's side of "Sign in with iPhone": open a request, poll it, and
// complete it with the 6-digit code the approving iPhone displays.
// Exports: SigninRequesting, SigninClient, SigninTicket, SigninProgress, SigninError.

import Foundation

public protocol SigninRequesting: Sendable {
    func open(server: URL, deviceLabel: String) async throws -> SigninTicket
    func status(_ ticket: SigninTicket) async throws -> SigninProgress
    func complete(
        _ ticket: SigninTicket, code: String, signing: PairingSigningRegistration?
    ) async throws -> PairingRedemptionGrant
}

/// A request the Mac opened. `pollToken` is a credential: keep it in memory only.
public struct SigninTicket: Equatable, Sendable {
    public let link: SigninLink
    public let pollToken: String
    public let expiresAt: Date
}

public enum SigninProgress: String, Equatable, Sendable, Decodable {
    case pending, approved, rejected, completed, expired
}

public enum SigninError: Error, Equatable, Sendable {
    case tooManyRequests
    case notFound
    /// The code was wrong, or the request was rejected, expired or already used.
    case incorrectCodeOrInvalid
    case requestFailed(status: Int)
    case invalidResponse
}

public struct SigninClient: SigninRequesting {
    static let pollHeader = "X-Signin-Token"
    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func open(server: URL, deviceLabel: String) async throws -> SigninTicket {
        var request = Self.request(server, "requests", method: "POST")
        request.httpBody = try JSONEncoder().encode(["device_label": deviceLabel])
        let opened: OpenResponse = try await send(request)
        guard let link = SigninLink(serverURL: server, requestID: opened.requestID),
              let expiresAt = Self.date(opened.expiresAt), !opened.pollToken.isEmpty else {
            throw SigninError.invalidResponse
        }
        return SigninTicket(link: link, pollToken: opened.pollToken, expiresAt: expiresAt)
    }

    public func status(_ ticket: SigninTicket) async throws -> SigninProgress {
        var request = Self.request(ticket.link.serverURL, "status", method: "GET")
        request.setValue(ticket.pollToken, forHTTPHeaderField: Self.pollHeader)
        let response: StatusResponse = try await send(request)
        return response.status
    }

    /// The returned token is never logged here; the caller stores it.
    public func complete(
        _ ticket: SigninTicket, code: String, signing: PairingSigningRegistration? = nil
    ) async throws -> PairingRedemptionGrant {
        var request = Self.request(ticket.link.serverURL, "complete", method: "POST")
        request.setValue(ticket.pollToken, forHTTPHeaderField: Self.pollHeader)
        request.httpBody = try JSONEncoder().encode(CompleteRequest(code: code, signing: signing))
        let decoded: PairingRedeemResponse = try await send(request)
        guard !decoded.token.isEmpty, !decoded.boss.id.isEmpty else { throw SigninError.invalidResponse }
        return PairingRedemptionGrant(token: decoded.token, bossID: decoded.boss.id, signingKeyID: decoded.signingKeyID)
    }

    private static func request(_ server: URL, _ path: String, method: String) -> URLRequest {
        let url = server.appendingPathComponent("api").appendingPathComponent("signin").appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SigninError.invalidResponse }
        switch http.statusCode {
        case 200..<300: break
        case 400: throw SigninError.incorrectCodeOrInvalid
        case 404: throw SigninError.notFound
        case 429: throw SigninError.tooManyRequests
        default: throw SigninError.requestFailed(status: http.statusCode)
        }
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else { throw SigninError.invalidResponse }
        return decoded
    }

    static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private struct OpenResponse: Decodable {
    let requestID: String
    let pollToken: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id", pollToken = "poll_token", expiresAt = "expires_at"
    }
}

private struct StatusResponse: Decodable {
    let status: SigninProgress
}

private struct CompleteRequest: Encodable {
    let code: String
    let signing: PairingSigningRegistration?
}
