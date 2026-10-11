// Controlled service for startup overlap and acknowledgement regression tests.
// Exports PanelsStartupAPI with held panel-list reads and counted questionnaires.
// Dependencies: HibossKit service protocols and Swift continuations.

import Foundation
@testable import HibossKit

actor PanelsStartupAPI: PanelsServing, QuestionnaireServing {
    nonisolated let questionnaireScope = "startup-tests"
    private var panelGate: CheckedContinuation<Void, Never>?
    private var panelWaiter: CheckedContinuation<Void, Never>?
    private var hold = true
    private var panels: [PanelMetadata] = []

    func setPanels(_ value: [PanelMetadata]) { panels = value }
    private(set) var panelReads = 0
    private(set) var questionReads = 0

    func waitForPanels() async {
        if panelGate != nil { return }
        await withCheckedContinuation { panelWaiter = $0 }
    }

    func releasePanels() {
        panelGate?.resume()
        panelGate = nil
    }

    func fetchPanels() async throws -> [PanelMetadata] {
        panelReads += 1
        if hold {
            hold = false
            await withCheckedContinuation {
                panelGate = $0
                panelWaiter?.resume()
                panelWaiter = nil
            }
        }
        return panels
    }

    func fetchPendingQuestionnaires() async throws -> [PendingQuestionnaire] {
        questionReads += 1
        return []
    }

    func fetchPanel(_ panelID: String) async throws -> PanelDetail { throw HibossAPIError.invalidResponse }
    func fetchPanelState(_ panelID: String) async throws -> PanelRelaySnapshot {
        throw HibossAPIError.invalidResponse
    }
    func updatePanelPreference(_ panelID: String, command: PanelPreferenceCommand) async throws
        -> PanelPreference { throw HibossAPIError.invalidResponse }
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
}
