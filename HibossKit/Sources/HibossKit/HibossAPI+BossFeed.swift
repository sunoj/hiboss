// Passive boss feed transport, independent of the option delivery stream.
// Exports: HibossAPI.feedStream and BossFeedDecoder using inbox HistoryMessage models.
// Dependencies: Foundation URLSession and shared authenticated request helpers.

import Foundation

extension HibossAPI {
    public func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await consumeFeed(into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func consumeFeed(
        into continuation: AsyncThrowingStream<HistoryMessage, Error>.Continuation
    ) async throws {
        let endpoint = apiURL.appendingPathComponent("stream").appending(
            queryItems: [URLQueryItem(name: "feed", value: "true")]
        )
        let request = authorizedRequest(url: endpoint, method: "GET", acceptsSSE: true)
        let (bytes, response) = try await session.bytes(for: request)
        try validate(response)
        var decoder = BossFeedDecoder()
        for try await line in bytes.lines {
            try Task.checkCancellation()
            if let message = decoder.consume(line: line) {
                continuation.yield(message)
            }
        }
    }
}

/// The boss feed emits one complete JSON message per data line. Decode immediately:
/// URLSession's lines sequence may omit blank SSE separators on a live connection.
struct BossFeedDecoder {
    private var eventName = "message"
    private let decoder = JSONDecoder()

    mutating func consume(line: String) -> HistoryMessage? {
        if line.isEmpty { eventName = "message"; return nil }
        if line.hasPrefix("event:") {
            eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            return nil
        }
        guard line.hasPrefix("data:") else { return nil }
        defer { eventName = "message" }
        guard eventName == "message" else { return nil }
        return try? decoder.decode(HistoryMessage.self, from: Data(line.dropFirst(5).utf8))
    }
}
