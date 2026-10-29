// Static multi-panel fixture service and production panel composition for CPU measurement.
// Exports: PerfSurveyPanelsAPI and PerfSurveyPanelSurface; no demo producers or live network.
// Dependencies: HibossKit, SwiftUI and the existing StubPanelsService fixture.

import HibossKit
import SwiftUI
@testable import HibossIsland

actor PerfSurveyPanelsAPI: PanelsServing {
    let panels: [PanelMetadata]
    let details: [String: PanelDetail]

    init(count: Int) async throws {
        let seed = try StubPanelsService(populated: true)
        let detail = try await seed.fetchPanel("panel_1")
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let original = try decoder.decode([String: PanelValue].self, from: encoder.encode(detail.metadata))
        let definition = try decoder.decode(PanelValue.self, from: encoder.encode(detail.definition))
        var metadata: [PanelMetadata] = []
        var expanded: [String: PanelDetail] = [:]
        for index in 0..<count {
            let id = "panel-\(index)"
            var fields = original
            fields["panelId"] = .string(id)
            fields["taskKey"] = .string(id)
            fields["title"] = .string("Validation \(index)")
            metadata.append(try decoder.decode(PanelMetadata.self, from: encoder.encode(fields)))
            fields["definition"] = definition
            expanded[id] = try decoder.decode(PanelDetail.self, from: encoder.encode(fields))
        }
        panels = metadata
        details = expanded
    }

    func fetchPanels() async throws -> [PanelMetadata] { panels }
    func fetchPanel(_ panelID: String) async throws -> PanelDetail {
        guard let detail = details[panelID] else { throw TestError.rejected }
        return detail
    }
    func fetchPanelState(_ panelID: String) async throws -> PanelRelaySnapshot {
        PanelRelaySnapshot(panelID: panelID, definitionRevision: 1, epoch: nil, sequence: 0,
            task: .object(["done": .number(3)]))
    }
    func updatePanelPreference(_ panelID: String, command: PanelPreferenceCommand) async throws
        -> PanelPreference { throw TestError.rejected }
}

struct PerfSurveyPanelSurface: View {
    @ObservedObject var model: PanelsModel
    var body: some View {
        ScrollView {
            if let tile = model.selectedTile {
                DashboardPanelDetail(tile: tile, model: model)
            } else {
                DashboardPanelsSection(model: model)
            }
        }
    }
}
