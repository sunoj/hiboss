// Shared panel tile metadata and relay freshness presentation state.
// Exports: PanelTile and PanelFreshness.
// Dependencies: PanelFixture, PanelStore, PanelDemoProducer, and SwiftUI Color.

import SwiftUI

@MainActor
public struct PanelTile: Identifiable {
    public var metadata: PanelMetadata?
    public var lifecycle: PanelLifecycle { metadata?.lifecycle ?? .running }
    public var preference: PanelPreference { metadata?.preference ?? .automatic }
    public let id: String
    public let fixture: PanelFixture
    public let store: PanelStore
    public let producer: PanelDemoProducer?
    public let agentID: String?
    public let agentName: String?
    public let sessionLabel: String?
    public let definitionRevision: Int?
    public let order: Int

    public init(
        id: String,
        fixture: PanelFixture,
        store: PanelStore,
        producer: PanelDemoProducer?,
        agentID: String?,
        agentName: String?,
        sessionLabel: String?,
        definitionRevision: Int?,
        order: Int,
        metadata: PanelMetadata? = nil
    ) {
        self.metadata = metadata
        self.id = id
        self.fixture = fixture
        self.store = store
        self.producer = producer
        self.agentID = agentID
        self.agentName = agentName
        self.sessionLabel = sessionLabel
        self.definitionRevision = definitionRevision
        self.order = order
    }

    public var sourceLabel: String {
        if let producer { return producer.name }
        let who = agentName ?? agentID.map { "agent \($0.prefix(8))" } ?? "Unattributed"
        guard let sessionLabel, !sessionLabel.isEmpty else { return who }
        return "\(who) · \(sessionLabel)"
    }
}

public enum PanelFreshness {
    case live, stale, offline, awaitingData, task(PanelTaskState)

    public var title: String {
        switch self {
        case .awaitingData: "Awaiting data"
        case let .task(state): state.title
        case .live: "Live"
        case .stale: "Stale"
        case .offline: "Offline"
        }
    }

    public var symbol: String {
        switch self {
        case .awaitingData: "hourglass"
        case let .task(state): state.symbol
        case .live: "dot.radiowaves.left.and.right"
        case .stale: "clock.badge.exclamationmark"
        case .offline: "wifi.slash"
        }
    }

    public var color: Color {
        switch self {
        case .awaitingData: .secondary
        case let .task(state): state == .failed ? .red : state == .completed ? .green : .secondary
        case .live: .green
        case .stale: .orange
        case .offline: .secondary
        }
    }
}
