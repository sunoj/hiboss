// Checks Home's conservative coverage gate for missing panel data.
// Exports HomePendingCoverageTests; empty cached requests cannot authorize all-clear.
// Dependencies: XCTest, InboxStore, HomeView and the shared PanelsModel fixtures.

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
        let home = HomeView(inbox: inbox, sessionAPI: nil, panels: panels)
        XCTAssertEqual(home.attentionStatus, "Waiting for: Panels.")
    }
}
