// iOS Home required-input contract, separate from macOS option delivery.
// Exports RequiredInputServing and RequiredInputEvent.
// Depends on shared HistoryMessage and MessageID models.

import Foundation

public enum RequiredInputEvent: Equatable, Sendable {
    case message(HistoryMessage)
    case resolved(MessageID)
    case ready
}

public protocol RequiredInputServing: Sendable {
    func fetchRequiredInputs() async throws -> [HistoryMessage]
    func requiredInputStream() async -> AsyncThrowingStream<RequiredInputEvent, Error>
}

public struct RequiredInputPage: Decodable, Sendable {
    public let messages: [HistoryMessage]
    public let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case messages
        case nextCursor = "next_cursor"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        messages = try values.decode([HistoryMessage].self, forKey: .messages)
        guard values.contains(.nextCursor) else {
            throw DecodingError.keyNotFound(
                CodingKeys.nextCursor,
                .init(codingPath: values.codingPath, debugDescription: "Missing pagination state")
            )
        }
        nextCursor = try values.decodeIfPresent(String.self, forKey: .nextCursor)
    }
}

public struct RequiredInputEventDecoder {
    private let decoder: JSONDecoder
    private var name = ""
    private var data = ""

    public init(decoder: JSONDecoder = JSONDecoder()) { self.decoder = decoder }

    public mutating func consume(line: String) throws -> RequiredInputEvent? {
        if line.hasPrefix("event:") {
            name = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            return nil
        }
        if line.hasPrefix("data:") {
            data += String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            return nil
        }
        guard line.isEmpty else { return nil }
        defer { name = ""; data = "" }
        switch name {
        case "message":
            return .message(try decoder.decode(HistoryMessage.self, from: Data(data.utf8)))
        case "resolved":
            return .resolved(try decoder.decode(ResolvedID.self, from: Data(data.utf8)).id)
        case "ready":
            guard (try JSONSerialization.jsonObject(with: Data(data.utf8))) is [String: Any] else {
                throw HibossAPIError.invalidResponse
            }
            return .ready
        default:
            return nil
        }
    }

    public func finish() throws {
        if ["message", "resolved", "ready"].contains(name) {
            throw HibossAPIError.invalidResponse
        }
    }
}

private struct ResolvedID: Decodable { let id: MessageID }
