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
                    try validate(response)
                    var parser = RequiredInputEventDecoder(decoder: decoder)
                    for try await line in bytes.lines {
                        if let event = try parser.consume(line: line) { continuation.yield(event) }
                    }
                    try parser.finish()
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
