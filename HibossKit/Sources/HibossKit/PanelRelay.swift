// Typed live-panel frames and the ordered client-side apply state machine.
// Exports: PanelRelayFrame, PanelRelayState, and PanelRelayApplyResult.
// Dependencies: Foundation Codable and PanelValue.

import Foundation

public struct PanelRelaySnapshot: Codable, Equatable, Sendable {
    public let panelID: String?
    public let definitionRevision: Int?
    public let epoch: String?
    public let sequence: Int
    public let task: PanelValue
    public let persistedAt: Int64?

    public init(
        panelID: String? = nil,
        definitionRevision: Int? = nil,
        epoch: String? = nil,
        sequence: Int,
        task: PanelValue,
        persistedAt: Int64? = nil
    ) {
        self.panelID = panelID
        self.definitionRevision = definitionRevision
        self.epoch = epoch
        self.sequence = sequence
        self.task = task
        self.persistedAt = persistedAt
    }

    enum CodingKeys: String, CodingKey {
        case panelID = "panelId", definitionRevision, epoch, sequence, task, persistedAt
    }
}

public struct PanelRelayOperation: Codable, Equatable, Sendable {
    public let operation: String
    public let path: String
    public let value: PanelValue?

    public init(operation: String, path: String, value: PanelValue? = nil) {
        self.operation = operation
        self.path = path
        self.value = value
    }

    enum CodingKeys: String, CodingKey {
        case operation = "op", path, value
    }
}

public struct PanelRelayPatch: Codable, Equatable, Sendable {
    public let panelID: String?
    public let definitionRevision: Int?
    public let epoch: String?
    public let baseSequence: Int?
    public let sequence: Int
    public let operations: [PanelRelayOperation]

    public init(
        panelID: String? = nil,
        definitionRevision: Int? = nil,
        epoch: String? = nil,
        baseSequence: Int? = nil,
        sequence: Int,
        operations: [PanelRelayOperation]
    ) {
        self.panelID = panelID
        self.definitionRevision = definitionRevision
        self.epoch = epoch
        self.baseSequence = baseSequence
        self.sequence = sequence
        self.operations = operations
    }

    enum CodingKeys: String, CodingKey {
        case panelID = "panelId", definitionRevision, epoch
        case baseSequence, sequence, operations = "ops"
    }
}

public enum PanelRelayFrame: Equatable, Sendable {
    case snapshot(PanelRelaySnapshot)
    case patch(PanelRelayPatch)
    case subscriptionRevoked
    case ignored

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(String.self, forKey: .kind) {
        case "state.snapshot": self = .snapshot(try PanelRelaySnapshot(from: decoder))
        case "state.patch": self = .patch(try PanelRelayPatch(from: decoder))
        case "subscription.revoked": self = .subscriptionRevoked
        default: self = .ignored
        }
    }

    private enum CodingKeys: String, CodingKey { case kind }
}

extension PanelRelayFrame: Decodable {}

public enum PanelRelayApplyResult: Equatable, Sendable {
    case ignored
    case installed
    case applied
    case resyncRequired
    case rejected
}

public struct PanelRelayState: Equatable, Sendable {
    public let panelID: String
    public let definitionRevision: Int
    public private(set) var epoch: String?
    public private(set) var sequence: Int
    public private(set) var task: PanelValue
    public private(set) var persistedAt: Int64?
    private var hasSnapshot = false

    public init(panelID: String, definitionRevision: Int, task: PanelValue = .object([:])) {
        self.panelID = panelID
        self.definitionRevision = definitionRevision
        epoch = nil
        sequence = -1
        self.task = task
        persistedAt = nil
    }

    public mutating func apply(_ frame: PanelRelayFrame) -> PanelRelayApplyResult {
        switch frame {
        case let .snapshot(snapshot): apply(snapshot)
        case let .patch(patch): apply(patch)
        case .subscriptionRevoked: .rejected
        case .ignored: .ignored
        }
    }

    private mutating func apply(_ snapshot: PanelRelaySnapshot) -> PanelRelayApplyResult {
        guard matches(panelID: snapshot.panelID, revision: snapshot.definitionRevision), snapshot.sequence >= sequence else {
            return .rejected
        }
        if let currentEpoch = epoch, snapshot.epoch != currentEpoch { return .rejected }
        guard snapshot.sequence >= 0 else { return .rejected }
        epoch = snapshot.epoch ?? epoch
        sequence = snapshot.sequence
        task = snapshot.task
        persistedAt = snapshot.persistedAt
        hasSnapshot = true
        return .installed
    }

    private mutating func apply(_ patch: PanelRelayPatch) -> PanelRelayApplyResult {
        guard matches(panelID: patch.panelID, revision: patch.definitionRevision), matches(epoch: patch.epoch) else {
            return .rejected
        }
        guard hasSnapshot else { return .resyncRequired }
        guard patch.sequence > sequence else { return .ignored }
        guard patch.baseSequence.map({ $0 == sequence }) ?? (patch.sequence == sequence + 1) else {
            return .resyncRequired
        }
        guard patch.sequence == sequence + 1 else { return .resyncRequired }
        guard let updated = patchedTask(operations: patch.operations) else { return .rejected }
        task = updated
        sequence = patch.sequence
        epoch = patch.epoch ?? epoch
        return .applied
    }

    private func matches(panelID incoming: String?, revision: Int?) -> Bool {
        (incoming == nil || incoming == panelID) && (revision == nil || revision == definitionRevision)
    }

    private func matches(epoch incoming: String?) -> Bool {
        incoming == nil || epoch == nil || incoming == epoch
    }

    private func patchedTask(operations: [PanelRelayOperation]) -> PanelValue? {
        var candidate = task
        for operation in operations {
            guard operation.path == "/task" || operation.path.hasPrefix("/task/"),
                  ["add", "replace", "remove"].contains(operation.operation) else { return nil }
            let path = operation.path == "/task" ? "" : String(operation.path.dropFirst(6))
            guard let updated = panelValuePatch(
                operation: operation.operation, path: path, value: operation.value, in: candidate
            ) else { return nil }
            candidate = updated
        }
        return candidate
    }
}

private func panelValuePatch(
    operation: String, path: String, value: PanelValue?, in root: PanelValue
) -> PanelValue? {
    guard path.isEmpty else {
        let segments = path.split(separator: "/", omittingEmptySubsequences: false).map(unescapePointer)
        return panelValuePatch(operation: operation, segments: segments[...], value: value, in: root)
    }
    if operation == "remove" { return .object([:]) }
    return value
}

private func panelValuePatch(
    operation: String, segments: ArraySlice<String>, value: PanelValue?, in root: PanelValue
) -> PanelValue? {
    guard let segment = segments.first else { return operation == "remove" ? .null : value }
    let rest = segments.dropFirst()
    guard case let .object(object) = root else { return nil }
    var copy = object
    if rest.isEmpty {
        if operation == "remove" { copy.removeValue(forKey: segment) }
        else if let value { copy[segment] = value } else { return nil }
        return .object(copy)
    }
    let child = copy[segment] ?? .object([:])
    guard let updated = panelValuePatch(operation: operation, segments: rest, value: value, in: child) else {
        return nil
    }
    copy[segment] = updated
    return .object(copy)
}

private func unescapePointer(_ segment: Substring) -> String {
    segment.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
}
