// Verifies inventory omission/error states and Box author/search filters without ranking.
// Exports SessionsV4Tests; service fixtures implement the shared read-only API boundary.
// Dependencies: XCTest, HibossKit, SessionFactsStore, and BoxFilter.

import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class SessionsV4Tests: XCTestCase {
    func testMissingInventoryFactsStayMissing() async {
        let model = SessionFactsStore()
        await model.load(id: "session", api: InventoryAPI(fails: false))
        XCTAssertEqual(model.session?.displayLabel, "hiboss/main")
        XCTAssertNil(model.session?.host)
        XCTAssertNil(model.session?.agentName)
        XCTAssertNil(model.session?.lastSeenAt)
        XCTAssertNil(model.session?.statusText)
        XCTAssertNil(model.error)
    }

    func testInventoryFailureKeepsEarlierFactsAndReportsError() async {
        let model = SessionFactsStore()
        await model.load(id: "session", api: InventoryAPI(fails: false))
        await model.load(id: "session", api: InventoryAPI(fails: true))
        XCTAssertEqual(model.session?.id, "session")
        XCTAssertNotNil(model.error)
    }

    func testSessionInventoryDatesAcceptServerUTCAndISOFormats() {
        let session = ProjectSession(id: "session", projectId: nil, projectSlug: nil, branch: nil,
                                     startedAt: "2026-10-09 14:15:16",
                                     lastSeenAt: "2026-10-09T14:15:16Z")
        XCTAssertNotNil(session.inventoryStartedDate)
        XCTAssertEqual(session.inventoryStartedDate, session.inventoryLastSeenDate)
        let invalid = ProjectSession(id: "session", projectId: nil, projectSlug: nil, branch: nil,
                                     startedAt: "unknown")
        XCTAssertNil(invalid.inventoryStartedDate)
        XCTAssertNil(invalid.inventoryLastSeenDate)
    }

    func testBoxAuthorFiltersNeverTreatAgentItemsAsMine() {
        let agent = BoxItem(id: "agent", bossID: "boss", bossName: "Boss", kind: .text, text: "Research",
                            createdAt: "", addedBy: .agent(id: "worker", name: "Researcher"))
        let boss = BoxItem(id: "mine", bossID: "boss", bossName: "Boss", kind: .image, text: "Reference",
                           createdAt: "")
        XCTAssertTrue(BoxFilter.agents.matches(agent, search: "researcher"))
        XCTAssertFalse(BoxFilter.mine.matches(agent, search: ""))
        XCTAssertTrue(BoxFilter.mine.matches(boss, search: "reference"))
        XCTAssertFalse(BoxFilter.agents.matches(boss, search: ""))
        XCTAssertTrue(BoxFilter.image.matches(boss, search: ""))
        XCTAssertFalse(BoxFilter.image.matches(agent, search: ""))
    }

    func testBoxSearchMatchesNotesProjectsTagsAndLinks() {
        let item = BoxItem(id: "link", bossID: "boss", bossName: "Boss", kind: .link,
                           url: "https://example.com",
                           note: "Soil report", project: "house", tags: ["survey"], createdAt: "")
        for query in ["soil", "HOUSE", "survey", "example.com"] {
            XCTAssertTrue(BoxFilter.all.matches(item, search: query), query)
        }
        XCTAssertFalse(BoxFilter.all.matches(item, search: "absent"))
    }

    func testBoxSearchLoadsBeyondFirstPage() async {
        let model = BoxStore(api: DemoBoxAPI())
        await model.refresh()
        XCTAssertNotNil(model.nextCursor)
        XCTAssertFalse(model.items.contains { $0.id == "demo-text-20" })
        await model.loadSearchPages()
        XCTAssertNil(model.nextCursor)
        XCTAssertTrue(model.items.contains { $0.id == "demo-text-20" })
    }

    func testSessionPanelsUseExactIdentityAndIgnoreAnotherScreensFilter() async {
        let model = PanelsModel(api: DemoNativePanelAPI(), demoMode: false, autoload: false)
        await model.load()
        XCTAssertEqual(model.tiles.count, 1)
        model.section = .archived
        XCTAssertEqual(SessionPanelCards(sessionID: "sess-deploy", model: model).tiles.map(\.id),
                       ["demo-panel"])
        XCTAssertTrue(SessionPanelCards(sessionID: "another-session", model: model).tiles.isEmpty)
    }

    func testExpiredDefaultKeepsDeadlineWithoutMarkingAnActiveOption() {
        let date = Date().addingTimeInterval(-60)
        let message = HistoryMessage(id: "decision", body: "Deploy?", direction: "agent_to_boss",
                                     status: "expired", priority: "normal",
                                     metadata: MessageMetadata(options: ["Yes", "No"], defaultOption: "No"),
                                     expiresAt: date.ISO8601Format(), createdAt: "")
        let timing = DecisionTiming(message: message)
        XCTAssertNotNil(timing.deadline)
        XCTAssertNil(timing.expiresAt)
        XCTAssertNil(timing.autoDefault)
        XCTAssertEqual(timing.declaredDefault, "No")
    }
}

private struct InventoryAPI: SessionsServing {
    let fails: Bool

    func projectSessions() async throws -> [ProjectSession] {
        if fails { throw HibossAPIError.invalidResponse }
        return [ProjectSession(id: "session", projectId: nil, projectSlug: "hiboss", branch: "main")]
    }
}
