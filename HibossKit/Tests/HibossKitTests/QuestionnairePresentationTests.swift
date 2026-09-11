// Verifies pending discovery projection and readable accepted answers without UI execution.
// Exports pure model tests for both native clients, including archived and expired cards.
// Dependencies: XCTest, typed panel fixtures, and shared questionnaire presentation.

import XCTest
@testable import HibossKit

@MainActor
final class QuestionnairePresentationTests: XCTestCase {
    func testPendingFilterFindsArchivedAndVisibilityExpiredPanels() throws {
        let model = PanelsModel(demoMode: false, autoload: false)
        model.clockTask?.cancel()
        let tile = try tile(placement: .archived)
        model.tiles = [tile]
        model.pendingQuestionnaires = [pending("optional", blocking: false), pending("required"), pending("expired", expiresAt: "2000-01-01T00:00:00Z")]
        XCTAssertEqual(model.visibleTiles.count, 0)
        model.section = .needsInput
        XCTAssertEqual(model.visibleTiles.map(\.id), [tile.id])
        XCTAssertEqual(model.pendingQuestionnaireCount, 2)
        model.tiles = [try self.tile(placement: .automatic)]
        XCTAssertEqual(model.visibleTiles.count, 1)
        model.section = .active
        XCTAssertEqual(model.visibleTiles.count, 0)
    }

    func testTerminalPanelsCannotKeepStalePendingBadges() throws {
        let model = PanelsModel(demoMode: false, autoload: false)
        model.clockTask?.cancel()
        model.tiles = [try tile(state: .completed)]
        model.pendingQuestionnaires = [pending("required")]
        model.section = .needsInput
        XCTAssertEqual(model.pendingQuestionnaireCount, 0)
        XCTAssertTrue(model.visibleTiles.isEmpty)
    }

    func testAcceptedChoicesUseLabelsAndKeepAdditionalAnswersReadable() {
        let spec = PanelSpec(root: "root", elements: [
            "root": PanelElement(type: "Stack", props: [:], children: ["choice", "multi"], on: nil),
            "choice": field("Select", "Channel", "/form/channel"),
            "multi": field("MultiSelect", "Environments", "/form/environments")
        ])
        let answers: PanelValue = .object(["channel": .string("ios"), "environments": .array([.string("mac"), .string("ios")]), "note": .string("Keep dark mode")])
        let rows = questionnaireAnswerRows(spec: spec, answers: answers)
        XCTAssertEqual(rows.map(\.label), ["Channel", "Environments", "note"])
        XCTAssertEqual(rows.map(\.value), ["iPhone", "Mac, iPhone", "Keep dark mode"])
    }

    func testAcceptedAnswersReadEscapedPathsWithoutDuplicatingFields() {
        let spec = PanelSpec(root: "field", elements: ["field": field("NumberInput", "Budget", "/form/a~1b~0c")])
        let rows = questionnaireAnswerRows(spec: spec, answers: .object(["a/b~c": .number(3.5)]))
        XCTAssertEqual(rows, [QuestionnaireAnswerRow(id: "/form/a~1b~0c", label: "Budget", value: "3.5")])
    }

    private func field(_ type: String, _ label: String, _ path: String) -> PanelElement {
        PanelElement(type: type, props: ["label": .string(label), "value": .object(["$bindState": .string(path)]),
            "options": .array([.object(["id": .string("ios"), "label": .string("iPhone")]), .object(["id": .string("mac"), "label": .string("Mac")])])], children: [], on: nil)
    }

    private func pending(_ id: String, blocking: Bool = true, expiresAt: String? = nil) -> PendingQuestionnaire {
        PendingQuestionnaire(requestId: id, panelId: "panel", requestRevision: 1, title: "Settings", blocking: blocking,
            expiresAt: expiresAt, createdAt: "2026-09-11T00:00:00Z")
    }

    private func tile(placement: PanelPlacement = .automatic, state: PanelTaskState = .running) throws -> PanelTile {
        let fixture = try XCTUnwrap(PanelFixtures.load().all.first)
        let lifecycle = PanelLifecycle(taskState: state, mode: "run", expectedUpdateIntervalSeconds: 15,
            expiresAt: "2000-01-01T00:00:00Z", terminalAt: nil, dismissAt: nil, dismissalPolicy: nil, result: nil)
        let metadata = PanelMetadata(serverTime: 0, lifecycle: lifecycle, preference: PanelPreference(preferenceVersion: 1, placement: placement),
            finalSnapshot: nil, supersedesPanelId: nil, panelId: "panel", agentId: "agent", agentName: nil, targetBossId: "boss",
            taskKey: "task", sessionId: "session", sessionLabel: nil, title: "Settings", catalogId: "hiboss.panel", catalogVersion: 1,
            definitionRevision: 1, metadataVersion: 1, summary: .object([:]), createdAt: "2026-09-11T00:00:00Z")
        return PanelTile(id: "panel", fixture: fixture, store: PanelStore(fixture: fixture), producer: nil, agentID: nil,
            agentName: nil, sessionLabel: nil, definitionRevision: 1, order: 0, metadata: metadata)
    }
}
