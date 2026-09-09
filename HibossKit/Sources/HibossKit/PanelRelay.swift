// V2 checkpoint frames and ordered native projection state.
// Exports PanelRelaySnapshot, PanelRelayFrame, and PanelRelayState.
// Dependencies: Foundation Codable and task-only PanelValue snapshots.

import Foundation

public struct PanelRelaySnapshot: Codable, Equatable, Sendable {
    public let serverTime: Int64
    public let protocolVersion: Int
    public let panelID: String
    public let definitionRevision: Int
    public let epoch: String?
    public let sequence: Int
    public let task: PanelValue
    public let persistedAt: Int64
    public let observationVersion: Int
    public let lastObservedAt: String?
    public let staleAt: String?
    public let expiresAt: String?
    public let leaseExpiresAt: String?

    public init(panelID: String, definitionRevision: Int, epoch: String?, sequence: Int, task: PanelValue,
                persistedAt: Int64 = 0, observationVersion: Int = 0, lastObservedAt: String? = nil,
                staleAt: String? = nil, expiresAt: String? = nil, leaseExpiresAt: String? = nil,
                serverTime: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.serverTime = serverTime
        protocolVersion = 2
        self.panelID = panelID; self.definitionRevision = definitionRevision; self.epoch = epoch
        self.sequence = sequence; self.task = task; self.persistedAt = persistedAt
        self.observationVersion = observationVersion; self.lastObservedAt = lastObservedAt
        self.staleAt = staleAt; self.expiresAt = expiresAt; self.leaseExpiresAt = leaseExpiresAt
    }
    enum CodingKeys: String, CodingKey {
        case serverTime, protocolVersion, panelID = "panelId", definitionRevision, epoch, sequence, task, persistedAt
        case observationVersion, lastObservedAt, staleAt, expiresAt, leaseExpiresAt
    }
}
public struct PanelRelayPatch: Decodable, Equatable, Sendable {
    public let checkpoint: PanelRelaySnapshot
    public let baseSequence: Int
    public init(checkpoint: PanelRelaySnapshot, baseSequence: Int) { self.checkpoint = checkpoint; self.baseSequence = baseSequence }
    public init(from decoder: Decoder) throws {
        checkpoint = try PanelRelaySnapshot(from: decoder)
        baseSequence = try decoder.container(keyedBy: CodingKeys.self).decode(Int.self, forKey: .baseSequence)
    }
    private enum CodingKeys: String, CodingKey { case baseSequence }
}
public enum PanelRelayFrame: Decodable, Equatable, Sendable {
    case snapshot(PanelRelaySnapshot), patch(PanelRelayPatch), observation(PanelRelaySnapshot)
    case metadataChanged, subscriptionRevoked, ignored
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(String.self, forKey: .kind) {
        case "state.snapshot": self = .snapshot(try PanelRelaySnapshot(from: decoder))
        case "state.patch": self = .patch(try PanelRelayPatch(from: decoder))
        case "state.observation": self = .observation(try PanelRelaySnapshot(from: decoder))
        case "panel.changed": self = .metadataChanged
        case "subscription.revoked": self = .subscriptionRevoked
        case "error":
            let code = try values.decode(String.self, forKey: .code)
            self = ["not_found", "permission_denied"].contains(code) ? .subscriptionRevoked : .ignored
        default: self = .ignored
        }
    }
    private enum CodingKeys: String, CodingKey { case kind, code }
}
public enum PanelRelayApplyResult: Equatable, Sendable { case ignored, installed, applied, resyncRequired, rejected }
public struct PanelRelayState: Equatable, Sendable {
    public let panelID: String
    public let definitionRevision: Int
    public private(set) var checkpoint: PanelRelaySnapshot?
    private var retiredEpochs: Set<String> = []
    public var epoch: String? { checkpoint?.epoch }
    public var sequence: Int { checkpoint?.sequence ?? -1 }
    public var task: PanelValue { checkpoint?.task ?? .object([:]) }
    public init(panelID: String, definitionRevision: Int) { self.panelID = panelID; self.definitionRevision = definitionRevision }

    public mutating func apply(_ frame: PanelRelayFrame) -> PanelRelayApplyResult {
        switch frame {
        case let .snapshot(value): return install(value, replacement: true)
        case let .observation(value):
            guard let checkpoint, value.epoch == epoch, value.sequence == sequence else { return .resyncRequired }
            guard value.observationVersion >= checkpoint.observationVersion, value.task == task else { return .rejected }
            return install(value, replacement: false)
        case let .patch(patch):
            guard checkpoint != nil else { return .resyncRequired }
            guard patch.checkpoint.epoch == epoch else { return .rejected }
            guard patch.checkpoint.sequence > sequence else { return .ignored }
            guard patch.baseSequence == sequence, patch.checkpoint.sequence == sequence + 1 else { return .resyncRequired }
            return install(patch.checkpoint, replacement: false)
        case .subscriptionRevoked: return .rejected
        case .metadataChanged, .ignored: return .ignored
        }
    }

    private mutating func install(_ value: PanelRelaySnapshot, replacement: Bool) -> PanelRelayApplyResult {
        guard value.protocolVersion == 2, value.panelID == panelID, value.definitionRevision == definitionRevision,
              value.sequence >= 0, value.observationVersion >= 0 else { return .rejected }
        if let incoming = value.epoch, retiredEpochs.contains(incoming) { return .rejected }
        if value.epoch == epoch, let checkpoint {
            guard value.sequence >= sequence, value.observationVersion >= checkpoint.observationVersion else { return .rejected }
        } else if let old = epoch {
            guard replacement else { return .rejected }
            retiredEpochs.insert(old)
        }
        checkpoint = value
        return replacement ? .installed : .applied
    }
}
