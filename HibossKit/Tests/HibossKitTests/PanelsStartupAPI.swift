// Controlled service for startup overlap and acknowledgement regression tests.
// Exports PanelsStartupAPI with held panel-list reads and counted questionnaires.
// Dependencies: HibossKit service protocols and Swift continuations.

import Foundation
import XCTest
@testable import HibossKit

actor PanelsStartupAPI: PanelsServing, QuestionnaireServing {
    nonisolated let questionnaireScope = "startup-tests"
    private var panelGate: CheckedContinuation<Void, Never>?
    private var panelWaiter: CheckedContinuation<Void, Never>?
    private var hold = true
    private var panels: [PanelMetadata] = []
    private var holdsQuestions = false
    private var questionGate: CheckedContinuation<Void, Never>?
    private var questionWaiter: CheckedContinuation<Void, Never>?

    func holdQuestions() { holdsQuestions = true }
    func holdPanels() { hold = true }
    func waitForQuestions() async {
        if questionGate != nil { return }
        await withCheckedContinuation { questionWaiter = $0 }
    }
    func releaseQuestions() {
        questionGate?.resume()
        questionGate = nil
    }

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
        let snapshot = panels
        if hold {
            hold = false
            await withCheckedContinuation {
                panelGate = $0
                panelWaiter?.resume()
                panelWaiter = nil
            }
        }
        return snapshot
    }

    func fetchPendingQuestionnaires() async throws -> [PendingQuestionnaire] {
        questionReads += 1
        if holdsQuestions {
            holdsQuestions = false
            await withCheckedContinuation {
                questionGate = $0
                questionWaiter?.resume()
                questionWaiter = nil
            }
        }
        return []
    }

    func fetchPanel(_ panelID: String) async throws -> PanelDetail {
        let metadata = try XCTUnwrap(panels.first { $0.panelId == panelID })
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(metadata))
            as? [String: Any])
        object["definition"] = [
            "definitionRevision": 1, "protocolVersion": 2, "catalogId": "hiboss.panel",
            "catalogVersion": 1, "createdAt": metadata.createdAt,
            "spec": ["root": "main", "elements": ["main": ["type": "Metric",
                "props": ["label": "Count", "value": 0], "children": []]]],
            "stateSchema": ["type": "object"], "initialState": ["task": [:]]
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(PanelDetail.self, from: data)
    }
    func fetchPanelState(_ panelID: String) async throws -> PanelRelaySnapshot {
        PanelRelaySnapshot(panelID: panelID, definitionRevision: 1, epoch: nil,
                           sequence: 0, task: .object([:]))
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
