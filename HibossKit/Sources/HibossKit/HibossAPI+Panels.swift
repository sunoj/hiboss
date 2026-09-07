// Typed panel list/detail contracts and authenticated reads for the boss wall.
// Exports: PanelsServing, PanelMetadata, PanelDetail, and PanelDefinition.
// Dependencies: Foundation Codable and HibossAPI request helpers.

import Foundation

public protocol PanelsServing: Sendable {
    func fetchPanels() async throws -> [PanelMetadata]
    func fetchPanel(_ panelID: String) async throws -> PanelDetail
}

public struct PanelListPage: Codable, Equatable, Sendable {
    public let panels: [PanelMetadata]
    public let nextCursor: String?
}

public struct PanelMetadata: Codable, Equatable, Sendable, Identifiable {
    public let panelId: String
    public let agentId: String
    public let agentName: String?
    public let targetBossId: String
    public let taskKey: String
    public let sessionId: String
    public let sessionLabel: String?
    public let title: String
    public let catalogId: String
    public let catalogVersion: Int
    public let definitionRevision: Int
    public let metadataVersion: Int
    public let summary: PanelValue
    public let createdAt: String

    public var id: String { panelId }
}

public struct PanelDetail: Decodable, Equatable, Sendable {
    public let metadata: PanelMetadata
    public let definition: PanelDefinition

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        definition = try container.decode(PanelDefinition.self, forKey: .definition)
        metadata = try PanelMetadata(
            panelId: container.decode(String.self, forKey: .panelId),
            agentId: container.decode(String.self, forKey: .agentId),
            agentName: container.decodeIfPresent(String.self, forKey: .agentName),
            targetBossId: container.decode(String.self, forKey: .targetBossId),
            taskKey: container.decode(String.self, forKey: .taskKey),
            sessionId: container.decode(String.self, forKey: .sessionId),
            sessionLabel: container.decodeIfPresent(String.self, forKey: .sessionLabel),
            title: container.decode(String.self, forKey: .title),
            catalogId: container.decode(String.self, forKey: .catalogId),
            catalogVersion: container.decode(Int.self, forKey: .catalogVersion),
            definitionRevision: container.decode(Int.self, forKey: .definitionRevision),
            metadataVersion: container.decode(Int.self, forKey: .metadataVersion),
            summary: container.decode(PanelValue.self, forKey: .summary),
            createdAt: container.decode(String.self, forKey: .createdAt)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case panelId, agentId, agentName, targetBossId, taskKey, sessionId, sessionLabel, title
        case catalogId, catalogVersion, definitionRevision, metadataVersion, summary, createdAt
        case definition
    }
}

public struct PanelDefinition: Codable, Equatable, Sendable {
    public let definitionRevision: Int
    public let protocolVersion: Int
    public let catalogId: String
    public let catalogVersion: Int
    public let spec: PanelSpec
    public let stateSchema: PanelValue
    public let initialState: PanelValue
    public let createdAt: String
}

public struct PanelSpec: Codable, Equatable, Sendable {
    public let root: String
    public let elements: [String: PanelElement]
}

public struct PanelElement: Codable, Equatable, Sendable {
    public let type: String
    public let props: [String: PanelValue]
    public let children: [String]
    public let on: [String: PanelAction]?
}

public struct PanelAction: Codable, Equatable, Sendable {
    public let action: String
    public let params: [String: PanelValue]?
}

public enum PanelValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([PanelValue])
    case object([String: PanelValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([PanelValue].self) { self = .array(value); return }
        self = .object(try container.decode([String: PanelValue].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}

extension HibossAPI: PanelsServing {
    /// Panels live under /api, not under /api/boss. The shared apiURL helper appends
    /// "boss", so reusing it asked for /api/boss/panels — a path the server does not
    /// serve, which fell through to boss auth and surfaced as "Boss Token was rejected".
    /// The token was never the problem.
    var panelsURL: URL { config.serverURL.appendingPathComponent("api").appendingPathComponent("panels") }

    public func fetchPanels() async throws -> [PanelMetadata] {
        try await decode(PanelListPage.self, from: panelsURL, context: "panel list").panels
    }

    public func fetchPanel(_ panelID: String) async throws -> PanelDetail {
        try await decode(
            PanelDetail.self,
            from: panelsURL.appendingPathComponent(panelID),
            context: "panel detail"
        )
    }
}
