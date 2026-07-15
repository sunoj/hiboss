// HTTP and SSE client for the existing HiBoss boss API.
// Exports: HibossAPI with history, option streaming, replies, and verification.
// Dependencies: Foundation URLSession, BossServing, and OptionMessage Codable.

import Foundation

enum HibossAPIError: Error, LocalizedError {
    case invalidResponse
    case requestFailed(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The server returned an invalid response."
        case let .requestFailed(status, message):
            message.isEmpty ? "Server request failed (HTTP \(status))." : message
        }
    }
}

final class HibossAPI: BossServing, @unchecked Sendable {
    private let config: ConnectionConfig
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(config: ConnectionConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> {
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

    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome {
        let endpoint = messageEndpoint(messageID).appendingPathComponent("reply")
        var request = authorizedRequest(url: endpoint, method: "POST")
        request.httpBody = try JSONEncoder().encode(ReplyPayload(body: choice))
        let (_, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 409 {
            return .alreadyResolved
        }
        try validate(response)
        return .accepted
    }

    func fetchHistory() async throws -> [HistoryMessage] {
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

    func verifyConnection() async throws {
        let endpoint = apiURL.appendingPathComponent("me")
        let request = authorizedRequest(url: endpoint, method: "GET")
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

    private func authorizedRequest(
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

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw HibossAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HibossAPIError.requestFailed(status: http.statusCode, message: "")
        }
    }
}

private struct ReplyPayload: Encodable {
    let body: String
}

struct SSEEventDecoder {
    let decoder: JSONDecoder
    private var eventName = "message"
    private var dataLines: [String] = []

    init(decoder: JSONDecoder) {
        self.decoder = decoder
    }

    mutating func consume(line: String) -> BossEvent? {
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

    mutating func finish() -> BossEvent? {
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
