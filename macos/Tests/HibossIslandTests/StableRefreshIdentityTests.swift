// Verifies account changes discard an already-mounted questionnaire editor.
// Reuses the panel ID while the new account's questionnaire read is held.
// Dependencies: AppKit hosting, SwiftUI, XCTest, and production PanelsModel.

import AppKit
import SwiftUI
import XCTest
@testable import HibossKit
@testable import HibossIsland

extension StableRefreshTests {
    func testAccountChangeDisposesEditorEvenWhenPanelIDIsReused() async throws {
        let api = try StableReadAPI(populatedPanels: true)
        let panels = PanelsModel(api: api, demoMode: false, autoload: false)
        panels.clockTask?.cancel()
        await panels.load()
        let tile = try XCTUnwrap(panels.tiles.first)
        await api.setRecords([editorRecord(panelID: tile.id)])
        panels.open(tile.id)
        let host = NSHostingView(rootView: IdentityEditorHost(panels: panels))
        let window = try await StableWindowSupport.show(host)
        defer { window.close() }
        try await waitForCondition { !self.editorFields(host).isEmpty }
        let firstReads = await api.editorReads
        XCTAssertEqual(firstReads, 1)
        await api.hold(.editor)
        panels.connectionDidChange()
        XCTAssertNil(panels.selectedTile)
        panels.reconciliationTask?.cancel()
        panels.reconciliationTask = nil
        panels.tiles = [PanelTile(id: tile.id, fixture: tile.fixture,
            store: PanelStore(fixture: tile.fixture),
            producer: nil, agentID: tile.agentID, agentName: tile.agentName, sessionLabel: tile.sessionLabel,
            definitionRevision: tile.definitionRevision, order: tile.order, metadata: tile.metadata)]
        panels.open(tile.id)
        await api.waitUntilHeld(.editor)
        XCTAssertTrue(editorFields(host).isEmpty,
            "Old questionnaire controls must be disposed before new data")
        await api.release(.editor)
        try await waitForCondition { !self.editorFields(host).isEmpty }
        let currentReads = await api.editorReads
        XCTAssertEqual(currentReads, 2, "The new identity must create a fresh questionnaire read")
    }

    private func editorFields(_ host: NSView) -> [NSTextField] {
        StableWindowSupport.descendants(host).compactMap { $0 as? NSTextField }.filter(\.isEditable)
    }

    private func editorRecord(panelID: String) -> QuestionnaireRecord {
        let spec = PanelSpec(root: "count", elements: ["count": PanelElement(type: "NumberInput",
            props: ["label": .string("Count"), "value": .object(["$bindState": .string("/form/count")])],
            children: [], on: nil)])
        let definition = QuestionnaireDefinition(title: "Account settings", kind: "intake", blocking: true,
            formSpec: spec, answerSchema: .object([:]), defaults: .object(["count": .number(3)]),
            context: .object([:]))
        return QuestionnaireRecord(requestId: "identity-editor", panelId: panelID, requestRevision: 1,
            definitionRevision: 1, state: "open", expiresAt: nil, withdrawalReason: nil,
            definition: definition, submission: nil)
    }
}

private struct IdentityEditorHost: View {
    @ObservedObject var panels: PanelsModel

    var body: some View {
        if let tile = panels.selectedTile {
            PanelQuestionnairesView(tile: tile, panels: panels)
        }
    }
}
