// Checks Home's conservative coverage gate for missing panel data.
// Exports HomePendingCoverageTests; empty cached requests cannot authorize all-clear.
// Dependencies: XCTest, InboxStore, HomeContent and the shared PanelsModel fixtures.

import XCTest
@testable import HiBoss
@testable import HibossKit

@MainActor
final class HomePendingCoverageTests: XCTestCase {
    func testPanelWithoutCurrentDataKeepsHomePending() async {
        let api = ControlledInputAPI()
        let inbox = InboxStore(decisionAlertsEnabled: false)
        inbox.start(api: api)
        defer { inbox.stop() }
        await api.waitForStream(0)
        await api.sendReady(to: 0)
        await inbox.refresh()
        XCTAssertEqual(inbox.connectionState, .connected)
        let panels = PanelsModel(demoMode: true, autoload: false)
        panels.clockTask?.cancel()
        panels.lastUpdated.removeAll()
        panels.hasCompleteQuestionnaires = true
        XCTAssertFalse(panels.tiles.isEmpty)
        let home = HomeContent(inbox: inbox, panels: panels, actionNote: .constant(nil),
                               decisionID: .constant(nil), showingDecision: .constant(false),
                               sessionRoute: .constant(nil))
        XCTAssertEqual(home.attentionStatus, "Waiting for: Panels.")
    }

    func testCheckedOfflineAndStaleProducersDoNotKeepHomeCheckingForever() async throws {
        let api = ControlledInputAPI()
        let inbox = InboxStore(decisionAlertsEnabled: false)
        inbox.start(api: api)
        defer { inbox.stop() }
        await api.sendReady(to: 0)
        await inbox.refresh()
        let panels = PanelsModel(demoMode: false, autoload: false)
        panels.clockTask?.cancel()
        let fixture = try XCTUnwrap(PanelFixtures.load().all.first)
        let tile = PanelTile(id: "producer", fixture: fixture, store: PanelStore(fixture: fixture),
                             producer: nil, agentID: "agent", agentName: nil, sessionLabel: nil,
                             definitionRevision: 1, order: 0)
        panels.tiles = [tile]
        panels.loadState = .loaded
        panels.hasCompleteQuestionnaires = true
        let home = HomeContent(inbox: inbox, panels: panels, actionNote: .constant(nil),
                               decisionID: .constant(nil), showingDecision: .constant(false),
                               sessionRoute: .constant(nil))
        XCTAssertEqual(home.attentionStatus, "Waiting for: Panels.", "An unread projection remains unknown")
        let now = Date()
        for leaseOffset in [-60.0, 60.0] {
            panels.receive(.snapshot(PanelRelaySnapshot(
                panelID: tile.id, definitionRevision: 1, epoch: "connected", sequence: 0,
                task: .object([:]), lastObservedAt: now.addingTimeInterval(-120).ISO8601Format(),
                staleAt: now.addingTimeInterval(-60).ISO8601Format(),
                leaseExpiresAt: now.addingTimeInterval(leaseOffset).ISO8601Format()
            )), for: tile.id)
            switch panels.freshness(for: tile) {
            case .offline, .stale: break
            default: XCTFail("The producer must retain its offline or stale state")
            }
            XCTAssertNil(home.attentionStatus, "A checked producer's age is not an unfinished connection")
        }
        panels.liveSubscriptions.remove(tile.id)
        XCTAssertEqual(home.attentionStatus, "Waiting for: Panels.", "A lost relay still blocks coverage")
        panels.liveSubscriptions.insert(tile.id)
        panels.hasCompleteQuestionnaires = false
        XCTAssertEqual(home.attentionStatus, "Waiting for: Questionnaires.")
    }
}
