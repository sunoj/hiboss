// Server-shaped demo panel and durable questionnaire for held native loading/action states.
// Exports DemoPanelServices and DemoNativePanelAPI, selected only by HIBOSS_DEMO_NATIVE_PANEL.
// Dependencies: HibossKit, DemoDelay and small synthetic wire fixtures.

import Foundation
import HibossKit

enum DemoPanelServices {
    static func make() -> any PanelsServing {
        if ProcessInfo.processInfo.environment["HIBOSS_DEMO_METRIC_PANEL"] == "1" {
            return DemoMetricPanelAPI()
        }
        return ProcessInfo.processInfo.environment["HIBOSS_DEMO_NATIVE_PANEL"] == "1"
            ? DemoNativePanelAPI() : DemoHomePanelsAPI()
    }
}

actor DemoNativePanelAPI: PanelsServing, QuestionnaireServing {
    nonisolated let questionnaireScope = "native-demo-\(UUID().uuidString)"
    private var submission: QuestionnaireSubmission?
    private var preference = PanelPreference.automatic

    init() {
        let delay = ProcessInfo.processInfo.environment["HIBOSS_DEMO_RECOVERY_DELAY_MS"] ?? ""
        guard (Int(delay) ?? 0) > 0 else { return }
        let key = "hiboss.questionnaire.\(questionnaireScope).demo-boss.demo-intake.1"
        let draft = Data("{\"answers\":{\"target\":\"TestFlight\"},\"submissionID\":\"demo-pending\"}".utf8)
        UserDefaults.standard.set(draft, forKey: key)
    }

    func fetchPanels() async throws -> [PanelMetadata] {
        try await DemoDelay.wait("PANELS")
        var metadata: PanelMetadata = try decode(Self.panelJSON)
        metadata.preference = preference
        return [metadata]
    }

    func fetchPanel(_ panelID: String) async throws -> PanelDetail { try decode(Self.panelJSON) }

    func fetchPanelState(_ panelID: String) async throws -> PanelRelaySnapshot {
        PanelRelaySnapshot(panelID: panelID, definitionRevision: 1, epoch: "demo", sequence: 1,
                           task: .object([:]), lastObservedAt: Date().ISO8601Format())
    }

    func updatePanelPreference(_ panelID: String, command: PanelPreferenceCommand) async throws
        -> PanelPreference
    {
        try await DemoDelay.wait("PREFERENCE")
        let placement = command.placement?.rawValue ?? "automatic"
        preference = try decode("""
        {"preferenceVersion":2,"placement":"\(placement)"}
        """)
        return preference
    }

    func fetchPendingQuestionnaires() async throws -> [PendingQuestionnaire] {
        try await DemoDelay.wait("QUESTIONNAIRES")
        guard submission == nil else { return [] }
        return [try decode("""
        {"requestId":"demo-intake","panelId":"demo-panel","requestRevision":1,
         "title":"Release checklist","blocking":true,"createdAt":"2026-10-07T00:00:00Z"}
        """)]
    }

    func fetchQuestionnaires(panelID: String) async throws -> [QuestionnaireRecord] {
        try await DemoDelay.wait("QUESTIONS")
        return [try await fetchQuestionnaire("demo-intake")]
    }

    func fetchQuestionnaire(_ id: String) async throws -> QuestionnaireRecord {
        guard
            var object = try JSONSerialization.jsonObject(with: Data(Self.questionJSON.utf8))
                as? [String: Any]
        else { throw HibossAPIError.invalidResponse }
        if let submission {
            object["state"] = "accepted"
            object["submission"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(submission))
        }
        return try JSONDecoder().decode(
            QuestionnaireRecord.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func fetchQuestionnaireSubmission(requestID: String, submissionID: String) async throws
        -> QuestionnaireSubmission
    {
        try await DemoDelay.wait("RECOVERY")
        guard let submission else { throw HibossAPIError.requestFailed(status: 404, message: "Missing") }
        return submission
    }

    func submitQuestionnaire(_ request: QuestionnaireRecord, bossID: String,
                             submissionID: String, answers: PanelValue) async throws -> QuestionnaireReceipt {
        try await DemoDelay.wait("SUBMISSION")
        let json = """
        {"submissionId":"\(submissionID)","requestId":"demo-intake","requestRevision":1,
         "answers":{},"acceptedAt":"2026-10-07T00:00:00Z","delivery":"pending"}
        """
        guard var object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        else { throw HibossAPIError.invalidResponse }
        object["answers"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(answers))
        submission = try JSONDecoder().decode(QuestionnaireSubmission.self,
                                               from: JSONSerialization.data(withJSONObject: object))
        return try decode(json)
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private static var panelJSON: String {
        """
        {"panelId":"demo-panel","agentId":"demo-agent","agentName":"release-agent",
         "targetBossId":"demo-boss","taskKey":"release","sessionId":"demo-session",
         "sessionLabel":"Release","title":"Release checklist","catalogId":"native-demo",
         "catalogVersion":1,"definitionRevision":1,"metadataVersion":1,"summary":{},
         "createdAt":"2026-10-07T00:00:00Z","serverTime":\(Int64(Date().timeIntervalSince1970 * 1000)),
         "lifecycle":{"taskState":"running","mode":"run","expectedUpdateIntervalSeconds":15},
         "preference":{"preferenceVersion":1,"placement":"automatic"},
         "definition":{"definitionRevision":1,"protocolVersion":2,"catalogId":"native-demo",
          "catalogVersion":1,"stateSchema":{},"initialState":{"task":{},"form":{}},
          "createdAt":"2026-10-07T00:00:00Z","spec":{"root":"summary","elements":{
           "summary":{"type":"Text","props":{"text":"Preparing the release"},"children":[]}}}}}
        """
    }

    private static let questionJSON = """
    {"requestId":"demo-intake","panelId":"demo-panel","requestRevision":1,
     "definitionRevision":1,"state":"open","definition":{"title":"Release checklist",
      "kind":"intake","blocking":true,"answerSchema":{},"defaults":{"target":"TestFlight"},
      "context":{},"formSpec":{"root":"form","elements":{
       "form":{"type":"Stack","props":{},"children":["target","notes","submit"]},
       "target":{"type":"TextInput","props":{"label":"Release target",
        "value":{"$bindState":"/form/target"}},"children":[]},
       "notes":{"type":"TextInput","props":{"label":"Release note",
        "value":{"$bindState":"/form/note"}},"children":[]},
       "submit":{"type":"Button","props":{"label":"Submit checklist"},
        "children":[],"on":{"press":{"action":"submitRequest"}}}}}}}
    """
}
