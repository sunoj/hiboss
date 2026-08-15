// HTTP and SSE client for the existing HiBoss boss API.
// Exports: HibossAPI with history, options, preferences, replies, and verification.
// Dependencies: Foundation URLSession, BossServing, and Codable domain contracts.

import Foundation

public enum HibossAPIError: Error, LocalizedError {
    case invalidResponse
    case requestFailed(status: Int, message: String)
    case decodingFailed(context: String, body: String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return kitL("The server returned an invalid response.")
        case let .requestFailed(status, message):
            if status == 401 || status == 403 {
                return kitL("That Boss Token was rejected. Check the token and try again.")
            }
            return message.isEmpty ? kitL("Server request failed (HTTP \(status)).") : message
        case let .decodingFailed(context, body):
            return kitL("Couldn't read \(context). Server sent: \(body.prefix(200))")
        }
    }

    /// A rejected credential (vs a transient/network failure) — callers stop
    /// retrying and prompt to reconnect instead of hammering with a dead token.
    public var isAuthFailure: Bool {
        if case let .requestFailed(status, _) = self { return status == 401 || status == 403 }
        return false
    }
}

public final class HibossAPI: BossServing, BossPreferencesServing, @unchecked Sendable {
    let config: ConnectionConfig
    let session: URLSession
    let decoder = JSONDecoder()
    /// Tags replies with the surface that produced them ("ios", "macos", "api").
    private let clientSource: String

    public init(config: ConnectionConfig, session: URLSession = .shared, clientSource: String = "api") {
        self.config = config
        self.session = session
        self.clientSource = clientSource
    }

    public func messageStream() async -> AsyncThrowingStream<BossEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await consumeStream(into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome {
        let endpoint = messageEndpoint(messageID).appendingPathComponent("reply")
        var request = authorizedRequest(url: endpoint, method: "POST")
        request.httpBody = try JSONEncoder().encode(ReplyPayload(body: choice, source: clientSource))
        let (_, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 409 {
            return .alreadyResolved
        }
        try validate(response)
        return .accepted
    }

    public func fetchHistory() async throws -> [HistoryMessage] {
        let endpoint = apiURL.appendingPathComponent("messages").appending(
            queryItems: [
                URLQueryItem(name: "direction", value: "all"),
                URLQueryItem(name: "limit", value: String(AppConstants.API.historyLimit)),
            ]
        )
        let request = authorizedRequest(url: endpoint, method: "GET")
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decoder.decode(HistoryResponse.self, from: data).messages
    }

    public func fetchPreferences() async throws -> BossPreferences {
        let endpoint = apiURL.appendingPathComponent("me").appendingPathComponent("preferences")
        let request = authorizedRequest(url: endpoint, method: "GET")
        let (data, response) = try await session.data(for: request)
        try validate(response)
        do {
            return try decoder.decode(BossPreferences.self, from: data)
        } catch {
            throw HibossAPIError.decodingFailed(
                context: "preferences", body: String(data: data, encoding: .utf8) ?? "<non-text>"
            )
        }
    }

    public func updatePreferences(_ preferences: BossPreferences) async throws -> BossPreferences {
        let endpoint = apiURL.appendingPathComponent("me").appendingPathComponent("preferences")
        var request = authorizedRequest(url: endpoint, method: "PUT")
        request.httpBody = try JSONEncoder().encode(preferences)
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decoder.decode(BossPreferences.self, from: data)
    }

    public func verifyConnection() async throws {
        let endpoint = apiURL.appendingPathComponent("me")
        let request = authorizedRequest(url: endpoint, method: "GET")
        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    /// Registers this device's APNs token so the server can push to it.
    public func registerDevice(
        token: String,
        bundleId: String,
        environment: String,
        platform: String = "ios"
    ) async throws {
        let endpoint = apiURL.appendingPathComponent("devices")
        var request = authorizedRequest(url: endpoint, method: "POST")
        request.httpBody = try JSONEncoder().encode(
            DeviceRegistration(token: token, bundleId: bundleId, environment: environment, platform: platform)
        )
        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    private var apiURL: URL {
        config.serverURL
            .appendingPathComponent("api")
            .appendingPathComponent("boss")
    }

    private func messageEndpoint(_ messageID: MessageID) -> URL {
        apiURL
            .appendingPathComponent("messages")
            .appendingPathComponent(messageID.rawValue)
    }

    private func consumeStream(
        into continuation: AsyncThrowingStream<BossEvent, Error>.Continuation
    ) async throws {
        let endpoint = apiURL.appendingPathComponent("stream").appending(
            queryItems: [URLQueryItem(name: "options", value: "true")]
        )
        let request = authorizedRequest(url: endpoint, method: "GET", acceptsSSE: true)
        let (bytes, response) = try await session.bytes(for: request)
        try validate(response)
        var eventDecoder = SSEEventDecoder(decoder: decoder)
        for try await line in bytes.lines {
            if let message = eventDecoder.consume(line: line) {
                continuation.yield(message)
            }
        }
        if let message = eventDecoder.finish() {
            continuation.yield(message)
        }
    }

    func authorizedRequest(
        url: URL,
        method: String,
        acceptsSSE: Bool = false
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = AppConstants.API.requestTimeout
        request.setValue("Bearer \(config.bossToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if acceptsSSE {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        return request
    }

    func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw HibossAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HibossAPIError.requestFailed(status: http.statusCode, message: "")
        }
    }

    var progressURL: URL {
        config.serverURL
            .appendingPathComponent("api")
            .appendingPathComponent("progress")
    }

    func decode<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        method: String = "GET",
        context: String
    ) async throws -> T {
        let request = authorizedRequest(url: url, method: method)
        let (data, response) = try await session.data(for: request)
        try validate(response)
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw HibossAPIError.decodingFailed(
                context: context,
                body: String(data: data, encoding: .utf8) ?? "<non-text>"
            )
        }
    }

    func send(_ method: String, url: URL) async throws {
        let request = authorizedRequest(url: url, method: method)
        let (_, response) = try await session.data(for: request)
        try validate(response)
    }
}

private struct ReplyPayload: Encodable {
    let body: String
    let source: String
}

private struct DeviceRegistration: Encodable {
    let token: String
    let bundleId: String
    let environment: String
    let platform: String
}

public struct SSEEventDecoder {
    let decoder: JSONDecoder
    private var eventName = "message"
    private var dataLines: [String] = []

    public init(decoder: JSONDecoder) {
        self.decoder = decoder
    }

    public mutating func consume(line: String) -> BossEvent? {
        if line.isEmpty { return finish() }
        if line.hasPrefix("event:") {
            eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            return nil
        }
        guard line.hasPrefix("data:") else { return nil }
        let data = line.dropFirst(5).drop(while: { $0 == " " })
        dataLines.append(String(data))
        return finish()
    }

    public mutating func finish() -> BossEvent? {
        guard !dataLines.isEmpty else { return nil }
        defer {
            dataLines.removeAll(keepingCapacity: true)
            eventName = "message"
        }
        let payload = dataLines.joined(separator: "\n")
        let data = Data(payload.utf8)
        if eventName == "resolved",
           let resolution = try? decoder.decode(OptionResolution.self, from: data) {
            return .resolved(resolution)
        }
        guard eventName == "message",
              let message = try? decoder.decode(OptionMessage.self, from: data) else {
            return nil
        }
        return .message(message)
    }
}
