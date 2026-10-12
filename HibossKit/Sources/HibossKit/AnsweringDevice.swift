// Registered device attribution supplied by the server on replies and resolutions.
// Exports AnsweringDevice and a display label that preserves legacy source fallback.
// Depends on Foundation Codable and resolutionSourceLabel.

import Foundation

public struct AnsweringDevice: Codable, Equatable, Sendable {
    public let clientID: String
    public let kind: String
    public let label: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case kind, label
    }

    public init(clientID: String, kind: String, label: String) {
        self.clientID = clientID
        self.kind = kind
        self.label = label
    }

    public var displayLabel: String? {
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? resolutionSourceLabel(kind) : name
    }
}

public extension MessageMetadata {
    var sourceLabel: String? { answeredBy?.displayLabel ?? resolutionSourceLabel(source) }
}

public extension ReplyOutcome {
    var answeredBy: AnsweringDevice? {
        if case let .acceptedOn(device) = self { return device }
        return nil
    }
}
