// HTTP client for the HiBoss push relay's registration API.
// Exports: PushRelayClient, PushRelayRegistration and PushRelayError.
// Dependencies: Foundation URLSession. Handles and secrets never reach a log.

import Foundation

struct PushRelayRegistration: Decodable, Equatable, Sendable {
    let handle: String
    let deviceSecret: String
}

enum PushRelayError: Error, Equatable {
    /// The relay no longer knows this secret; register again.
    case gone
    case failed(status: Int)
    case invalidResponse
}

struct PushRelayClient: Sendable {
    static let baseURL = URL(string: "https://push.hiboss.org")!

    let baseURL: URL
    let session: URLSession

    init(baseURL: URL = PushRelayClient.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// `POST /v1/registrations` → a fresh handle and device secret for this APNs token.
    func register(apnsToken: String, environment: String) async throws -> PushRelayRegistration {
        var request = request("v1/registrations", method: "POST")
        request.httpBody = try JSONEncoder().encode(TokenBody(apnsToken: apnsToken, environment: environment))
        let (data, response) = try await session.data(for: request)
        try check(response, expected: 201)
        guard let registration = try? JSONDecoder().decode(PushRelayRegistration.self, from: data) else {
            throw PushRelayError.invalidResponse
        }
        return registration
    }

    /// `PUT /v1/registrations/self` after an APNs token rotation; the handle stays the same.
    func update(deviceSecret: String, apnsToken: String, environment: String) async throws {
        var request = request("v1/registrations/self", method: "PUT", secret: deviceSecret)
        request.httpBody = try JSONEncoder().encode(TokenBody(apnsToken: apnsToken, environment: environment))
        let (_, response) = try await session.data(for: request)
        try check(response, expected: 204)
    }

    /// `DELETE /v1/registrations/self`; idempotent at the relay.
    func delete(deviceSecret: String) async throws {
        let (_, response) = try await session.data(for: request("v1/registrations/self", method: "DELETE",
                                                                 secret: deviceSecret))
        try check(response, expected: 204)
    }

    private func request(_ path: String, method: String, secret: String? = nil) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let secret { request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization") }
        return request
    }

    private func check(_ response: URLResponse, expected: Int) throws {
        guard let http = response as? HTTPURLResponse else { throw PushRelayError.invalidResponse }
        if http.statusCode == expected { return }
        if http.statusCode == 410 { throw PushRelayError.gone }
        throw PushRelayError.failed(status: http.statusCode)
    }
}

private struct TokenBody: Encodable {
    let apnsToken: String
    let environment: String
}
