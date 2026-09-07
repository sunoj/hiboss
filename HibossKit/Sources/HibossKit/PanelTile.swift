// Shared panel tile metadata and relay freshness presentation state.
// Exports: PanelTile and PanelFreshness.
// Dependencies: PanelFixture, PanelStore, PanelDemoProducer, and SwiftUI Color.

import SwiftUI

@MainActor
public struct PanelTile: Identifiable {
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
        order: Int
    ) {
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
    case live, stale, offline, fetched(Date), cachedFailure

    public var title: String {
        switch self {
        case .live: "Live"
        case .stale: "Stale"
        case .offline: "Offline"
        case let .fetched(date): "Fetched \(date.formatted(date: .omitted, time: .shortened))"
        case .cachedFailure: "Cached — fetch failed"
        }
    }

    public var symbol: String {
        switch self {
        case .live: "dot.radiowaves.left.and.right"
        case .stale: "clock.badge.exclamationmark"
        case .offline: "wifi.slash"
        case .fetched: "clock"
        case .cachedFailure: "exclamationmark.triangle"
        }
    }

    public var color: Color {
        switch self {
        case .live: .green
        case .stale, .cachedFailure: .orange
        case .offline, .fetched: .secondary
        }
    }
}
