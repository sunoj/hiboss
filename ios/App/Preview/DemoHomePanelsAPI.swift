// Supplies a known empty panel/questionnaire result for Home demo and UI tests.
// Exports DemoHomePanelsAPI without requiring a configured server or credentials.
// Dependencies: HibossKit panel and questionnaire service protocols.

import HibossKit
import Foundation

enum DemoTextAsk {
    static let message = HistoryMessage(
        id: "demo-text-ask", body: "Which dataset should I use?", agentName: "worker-data",
        direction: "agent_to_boss", status: "delivered", priority: "normal", mode: "blocking",
        createdAt: Date().addingTimeInterval(-120).ISO8601Format(),
        sessionId: "demo-text-session", sessionLabel: "Data export", sessionStatus: "waiting"
    )
}

struct DemoHomePanelsAPI: PanelsServing, QuestionnaireServing {
    let questionnaireScope = "home-demo"

    func fetchPanels() async throws -> [PanelMetadata] { [] }
    func fetchPendingQuestionnaires() async throws -> [PendingQuestionnaire] { [] }
    func fetchQuestionnaires(panelID: String) async throws -> [QuestionnaireRecord] { [] }

    func fetchPanel(_ panelID: String) async throws -> PanelDetail {
        throw HibossAPIError.invalidResponse
    }

    func fetchPanelState(_ panelID: String) async throws -> PanelRelaySnapshot {
        throw HibossAPIError.invalidResponse
    }

    func updatePanelPreference(_ panelID: String, command: PanelPreferenceCommand) async throws -> PanelPreference {
        throw HibossAPIError.invalidResponse
    }

    func fetchQuestionnaire(_ id: String) async throws -> QuestionnaireRecord {
        throw HibossAPIError.invalidResponse
    }

    func fetchQuestionnaireSubmission(requestID: String, submissionID: String) async throws -> QuestionnaireSubmission {
        throw HibossAPIError.invalidResponse
    }

    func submitQuestionnaire(_ request: QuestionnaireRecord, bossID: String,
                             submissionID: String, answers: PanelValue) async throws -> QuestionnaireReceipt {
        throw HibossAPIError.invalidResponse
    }
}
