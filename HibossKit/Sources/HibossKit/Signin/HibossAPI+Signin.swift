// The signed-in boss's side of "Sign in with iPhone": review a scanned request, approve it
// (the response carries the 6-digit code to display), or reject it. Admin or manager only.
// Exports: SigninRequestSummary, SigninApproval and the HibossAPI methods.

import Foundation

public struct SigninRequestSummary: Equatable, Sendable, Decodable {
    public let requestID: String
    public let deviceLabel: String
    /// Coarse "country · city" of the Mac's network, when the server knows it.
    public let origin: String?
    public let status: SigninProgress
    public let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id", deviceLabel = "device_label", origin, status, expiresAt = "expires_at"
    }
}

/// The code to show on the approving iPhone; the Mac's user types it to finish signing in.
public struct SigninApproval: Equatable, Sendable, Decodable {
    public let code: String
    public let expiresAt: String?
    public let deviceLabel: String?

    enum CodingKeys: String, CodingKey {
        case code, expiresAt = "expires_at", deviceLabel = "device_label"
    }
}

extension HibossAPI {
    /// 403 for a viewer, 404 for an unknown request.
    public func signinRequest(id: String) async throws -> SigninRequestSummary {
        try await signinCall(id: id, action: nil, method: "GET")
    }

    /// 409 when the request is no longer pending.
    public func approveSignin(id: String) async throws -> SigninApproval {
        try await signinCall(id: id, action: "approve", method: "POST")
    }

    public func rejectSignin(id: String) async throws {
        let _: SigninAck = try await signinCall(id: id, action: "reject", method: "POST")
    }

    private func signinCall<T: Decodable>(id: String, action: String?, method: String) async throws -> T {
        guard SigninLink.isValidRequestID(id) else { throw HibossAPIError.invalidResponse }
        var endpoint = config.serverURL
            .appendingPathComponent("api")
            .appendingPathComponent("boss")
            .appendingPathComponent("signin-requests")
            .appendingPathComponent(id)
        if let action { endpoint = endpoint.appendingPathComponent(action) }
        let (data, response) = try await session.data(for: authorizedRequest(url: endpoint, method: method))
        try validate(response)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HibossAPIError.decodingFailed(context: "sign-in request", body: "<unreadable>")
        }
    }
}

private struct SigninAck: Decodable {
    let ok: Bool
}
