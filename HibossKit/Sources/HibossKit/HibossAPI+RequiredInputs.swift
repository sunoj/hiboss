// Complete pending-input HTTP pagination and dedicated SSE stream for iOS Home.
// Exports HibossAPI RequiredInputServing conformance.
// Depends on the existing authorized request and response helpers.

import Foundation

extension HibossAPI: RequiredInputServing {
    public func fetchRequiredInputs() async throws -> [HistoryMessage] {
        var messages: [HistoryMessage] = []
        var cursor: String?
        var visited: Set<String> = []
        var ids: Set<MessageID> = []
        repeat {
            try Task.checkCancellation()
            var query: [URLQueryItem] = []
            if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
            let page = try await decode(
                RequiredInputPage.self,
                from: apiURL.appendingPathComponent("pending-inputs").appending(queryItems: query),
                context: "pending inputs"
            )
            try Task.checkCancellation()
            if page.messages.isEmpty && page.nextCursor != nil {
                throw HibossAPIError.invalidResponse
            }
            for message in page.messages where !ids.insert(message.id).inserted {
                throw HibossAPIError.invalidResponse
            }
            messages.append(contentsOf: page.messages)
            cursor = page.nextCursor
            if cursor == "" { throw HibossAPIError.invalidResponse }
            if let cursor, !visited.insert(cursor).inserted {
                throw HibossAPIError.invalidResponse
            }
        } while cursor != nil
        try Task.checkCancellation()
        return messages
    }

    public func requiredInputStream() async -> AsyncThrowingStream<RequiredInputEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = apiURL.appendingPathComponent("stream").appending(
                        queryItems: [URLQueryItem(name: "inputs", value: "true")]
                    )
                    let (bytes, response) = try await session.bytes(for: authorizedRequest(
                        url: url, method: "GET", acceptsSSE: true
                    ))
                    try await validate(response)
                    try await consumeRequiredInputBytes(bytes, into: continuation)
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func consumeRequiredInputBytes(
        _ bytes: URLSession.AsyncBytes,
        into continuation: AsyncThrowingStream<RequiredInputEvent, Error>.Continuation
    ) async throws {
        var parser = RequiredInputEventDecoder(decoder: decoder)
        var line = Data()
        // Foundation's lines sequence drops empty lines, which delimit SSE frames.
        // Decode UTF-8 only after a full line so chunk boundaries cannot split a character.
        for try await byte in bytes {
            try Task.checkCancellation()
            if byte != 10 {
                line.append(byte)
                continue
            }
            if line.last == 13 { line.removeLast() }
            if let event = try parser.consume(line: String(decoding: line, as: UTF8.self)) {
                continuation.yield(event)
            }
            line.removeAll(keepingCapacity: true)
        }
        if !line.isEmpty {
            _ = try parser.consume(line: String(decoding: line, as: UTF8.self))
        }
        try parser.finish()
    }
}
