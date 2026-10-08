// Cached budget panel followed by a discovery timeout for Home demo regressions.
// Exports DemoMetricPanelAPI, enabled by HIBOSS_DEMO_METRIC_PANEL.
// Dependencies: HibossKit shared metric example and synthetic panel wire metadata.

import Foundation
import HibossKit

actor DemoMetricPanelAPI: PanelsServing, QuestionnaireServing {
    nonisolated let questionnaireScope = "metric-demo"
    private let started = Date()

    func fetchPanels() async throws -> [PanelMetadata] {
        if Date().timeIntervalSince(started) > 5 {
            throw URLError(.timedOut, userInfo: [NSLocalizedDescriptionKey: "The request timed out."])
        }
        return [try detail().metadata]
    }

    func fetchPanel(_ panelID: String) async throws -> PanelDetail { try detail() }

    func fetchPanelState(_ panelID: String) async throws -> PanelRelaySnapshot {
        PanelRelaySnapshot(panelID: panelID, definitionRevision: 1, epoch: "demo", sequence: 1,
                           task: .object([:]), lastObservedAt: Date().ISO8601Format())
    }

    func fetchPendingQuestionnaires() async throws -> [PendingQuestionnaire] { [] }
    func fetchQuestionnaires(panelID: String) async throws -> [QuestionnaireRecord] { [] }
    func fetchQuestionnaire(_ id: String) async throws -> QuestionnaireRecord {
        throw HibossAPIError.invalidResponse
    }
    func fetchQuestionnaireSubmission(requestID: String, submissionID: String) async throws
        -> QuestionnaireSubmission { throw HibossAPIError.invalidResponse }
    func submitQuestionnaire(_ request: QuestionnaireRecord, bossID: String,
                             submissionID: String, answers: PanelValue) async throws -> QuestionnaireReceipt {
        throw HibossAPIError.invalidResponse
    }
    func updatePanelPreference(_ panelID: String, command: PanelPreferenceCommand) async throws
        -> PanelPreference { throw HibossAPIError.invalidResponse }

    private func detail() throws -> PanelDetail {
        let fixture = try PanelMetricExample.load()
        let spec = String(decoding: try JSONEncoder().encode(fixture.spec), as: UTF8.self)
        let json = """
        {"panelId":"metric-demo","agentId":"demo-agent","agentName":"house-agent",
         "targetBossId":"demo-boss","taskKey":"house","sessionId":"demo-session",
         "sessionLabel":"Mae Hia","title":"Mae Hia house · work in progress",
         "catalogId":"hiboss.panel","catalogVersion":1,"definitionRevision":1,"metadataVersion":1,
         "summary":{},
         "createdAt":"2026-10-07T00:00:00Z","serverTime":\(Int64(Date().timeIntervalSince1970 * 1000)),
         "lifecycle":{"taskState":"running","mode":"run","expectedUpdateIntervalSeconds":15},
         "preference":{"preferenceVersion":1,"placement":"automatic"},
         "definition":{"definitionRevision":1,"protocolVersion":2,"catalogId":"hiboss.panel",
          "catalogVersion":1,"stateSchema":{},"initialState":{"task":{}},
          "createdAt":"2026-10-07T00:00:00Z","spec":\(spec)}}
        """
        return try JSONDecoder().decode(PanelDetail.self, from: Data(json.utf8))
    }
}
