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
        let home = HomeContent(inbox: inbox, panels: panels, actionNote: .constant(nil), decisionID: .constant(nil),
                               showingDecision: .constant(false), sessionRoute: .constant(nil))
        XCTAssertEqual(home.attentionStatus, "Waiting for: Panels.")
    }
}
