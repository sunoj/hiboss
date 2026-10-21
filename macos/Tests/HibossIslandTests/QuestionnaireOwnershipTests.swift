// Blocking questionnaires are fetched, counted and announced with no main window open.
// Exports: QuestionnaireOwnershipTests with a stub questionnaire service and a recording center.
// Dependencies: XCTest, HibossKit panels/questionnaires, AppDelegate, and QuestionnaireNotifier.

import Foundation
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class QuestionnaireOwnershipTests: XCTestCase {
    func testAppOwnedPanelsHoldTheAllClearWithoutAMainWindow() async throws {
        let suite = "QuestionnaireOwnershipTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let api = try PendingQuestionnaireAPI(pending: [Self.questionnaire(createdAt: "2026-01-01T00:00:00Z")])
        let panels = PanelsModel(api: api, demoMode: false, autoload: false)
        let delegate = AppDelegate(settings: AppSettings(defaults: defaults, keychain: NoTokens()), panels: panels)
        delegate.observePanels()
        await panels.load()
        for _ in 0..<100 where !panels.pendingQuestionnaires.contains(where: \.blocking) {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(delegate.panels === panels)
        XCTAssertEqual(panels.pendingQuestionnaires.map(\.requestId), ["request-1"])
        XCTAssertFalse(delegate.overview.questionnaireCoverageComplete)
    }

    func testBlockingQuestionnairesAreAnnouncedOnceAtTheDecisionTier() async throws {
        let center = RecordingQuestionnaireCenter()
        var prefs = BossPreferences()
        let notifier = QuestionnaireNotifier(center: center, since: Date(timeIntervalSince1970: 1_790_000_000),
            isAuthorized: { true }, preferences: { prefs })
        let fresh = try Self.questionnaire(createdAt: "2026-10-21T12:00:00Z")
        let old = try Self.questionnaire(id: "old", createdAt: "2026-01-01T00:00:00Z")
        let optional = try Self.questionnaire(id: "optional", blocking: false, createdAt: "2026-10-21T12:00:00Z")
        await notifier.receive([fresh, old, optional])
        await notifier.receive([fresh])
        XCTAssertEqual(center.notices.map(\.requestID), ["request-1"])
        XCTAssertEqual(center.notices.first?.alert, MessageAlert(sound: true, level: .active))
        XCTAssertEqual(center.notices.first?.body, "Deploy window")
        prefs.decisionAlerts = false
        await notifier.receive([try Self.questionnaire(id: "quiet", createdAt: "2026-10-21T12:00:00Z")])
        XCTAssertEqual(center.notices.last?.alert, MessageAlert(sound: false, level: .passive))
    }

    static func questionnaire(id: String = "request-1", blocking: Bool = true,
                              createdAt: String) throws -> PendingQuestionnaire {
        let json = """
        {"requestId":"\(id)","panelId":"panel-1","requestRevision":1,"title":"Deploy window",
         "blocking":\(blocking),"expiresAt":null,"createdAt":"\(createdAt)"}
        """
        return try JSONDecoder().decode(PendingQuestionnaire.self, from: Data(json.utf8))
    }
}

private struct NoTokens: TokenStoring {
    func read() throws -> String? { nil }
    func write(_ token: String) throws {}
}

@MainActor
private final class RecordingQuestionnaireCenter: QuestionnaireNotifying {
    var notices: [QuestionnaireNotice] = []
    func postQuestionnaire(_ notice: QuestionnaireNotice) async throws { notices.append(notice) }
}

private actor PendingQuestionnaireAPI: PanelsServing, QuestionnaireServing {
    nonisolated let questionnaireScope = "mac-ownership"
    private let pending: [PendingQuestionnaire]

    init(pending: [PendingQuestionnaire]) throws { self.pending = pending }
    func fetchPanels() async throws -> [PanelMetadata] { [] }
    func fetchPanel(_ panelID: String) async throws -> PanelDetail { throw HibossAPIError.invalidResponse }
    func fetchPanelState(_ panelID: String) async throws -> PanelRelaySnapshot {
        throw HibossAPIError.invalidResponse
    }
    func updatePanelPreference(_ panelID: String, command: PanelPreferenceCommand) async throws
        -> PanelPreference { throw HibossAPIError.invalidResponse }
    func fetchPendingQuestionnaires() async throws -> [PendingQuestionnaire] { pending }
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
