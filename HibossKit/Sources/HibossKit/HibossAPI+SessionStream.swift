// Session-stream HTTP history and resumable SSE on HibossAPI.
// Exports: HibossAPI SessionStreamServing conformance and SessionSSEDecoder.
// Dependencies: SessionEvent models and the shared HibossAPI request helpers.

import Foundation

extension HibossAPI: SessionStreamServing {
    public func fetchSessionEvents(
        sessionID: String,
        after: Int? = nil,
        limit: Int = AppConstants.API.historyLimit
    ) async throws -> SessionEventsPage {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let after { items.append(URLQueryItem(name: "after", value: String(after))) }
        return try await decode(
            SessionEventsPage.self,
            from: sessionURL(sessionID).appendingPathComponent("events").appending(queryItems: items),
            context: "session events"
        )
    }

    public func sessionEventStream(
        sessionID: String,
        after: Int
    ) async -> AsyncThrowingStream<SessionStreamFrame, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await consumeSessionStream(
                        sessionID: sessionID, after: after, into: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func sessionURL(_ sessionID: String) -> URL {
        config.serverURL
            .appendingPathComponent("api")
            .appendingPathComponent("sessions")
            .appendingPathComponent(sessionID)
    }

    private func consumeSessionStream(
        sessionID: String,
        after: Int,
        into continuation: AsyncThrowingStream<SessionStreamFrame, Error>.Continuation
    ) async throws {
        let endpoint = sessionURL(sessionID).appendingPathComponent("stream").appending(
            queryItems: [URLQueryItem(name: "after", value: String(after))]
        )
        var request = authorizedRequest(url: endpoint, method: "GET", acceptsSSE: true)
        if after >= 0 {
            request.setValue(String(after), forHTTPHeaderField: "Last-Event-ID")
        }
        let (bytes, response) = try await session.bytes(for: request)
        try validate(response)
        var decoder = SessionSSEDecoder(decoder: self.decoder)
        for try await line in bytes.lines {
            if let frame = decoder.consume(line: line) {
                continuation.yield(frame)
            }
        }
        if let frame = decoder.finish() {
            continuation.yield(frame)
        }
    }
}

public struct SessionSSEDecoder {
    let decoder: JSONDecoder
    private var eventName = "session_event"
    private var dataLines: [String] = []

    public init(decoder: JSONDecoder) {
        self.decoder = decoder
    }

    public mutating func consume(line: String) -> SessionStreamFrame? {
        if line.isEmpty { return finish() }
        if line.hasPrefix(":") { return nil }
        if line.hasPrefix("event:") {
            eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            return nil
        }
        if line.hasPrefix("id:") { return nil }
        guard line.hasPrefix("data:") else { return nil }
        let data = line.dropFirst(5).drop(while: { $0 == " " })
        dataLines.append(String(data))
        return nil
    }

    public mutating func finish() -> SessionStreamFrame? {
        guard !dataLines.isEmpty else { return nil }
        defer {
            dataLines.removeAll(keepingCapacity: true)
            eventName = "session_event"
        }
        let payload = dataLines.joined(separator: "\n")
        let data = Data(payload.utf8)
        if eventName == "resync" { return .resync }
        guard eventName == "session_event",
              let event = try? decoder.decode(SessionEvent.self, from: data) else {
            return nil
        }
        return .event(event)
    }
}
