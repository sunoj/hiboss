// Local notifications for blocking questionnaires, once per request, at the server's decision tier.
// Exports: QuestionnaireNotice, QuestionnaireNotifying, and QuestionnaireNotifier.
// Dependencies: UserNotifications, HibossKit PendingQuestionnaire / MessageAlertPolicy, the center.

import Foundation
import HibossKit
import UserNotifications

struct QuestionnaireNotice: Equatable, Sendable {
    static let userInfoKey = "questionnairePanelID"
    let requestID: String
    let panelID: String
    let title: String
    let body: String
    let alert: MessageAlert

    init(questionnaire: PendingQuestionnaire, alert: MessageAlert) {
        requestID = questionnaire.requestId
        panelID = questionnaire.panelId
        title = L("Input needed")
        body = questionnaire.title
        self.alert = alert
    }
}

@MainActor
protocol QuestionnaireNotifying: AnyObject {
    func postQuestionnaire(_ notice: QuestionnaireNotice) async throws
}

/// The server pushes a blocking questionnaire once, on publication, at its decision tier. The
/// pending list carries no priority, so the tier is the one for `normal`. Requests created before
/// this notifier started were pushed then, and are not announced again.
@MainActor
final class QuestionnaireNotifier {
    private let center: any QuestionnaireNotifying
    private let isAuthorized: @MainActor () async -> Bool
    private let preferences: @MainActor () -> BossPreferences
    private let since: Date
    private var seen: Set<String> = []

    init(center: any QuestionnaireNotifying, since: Date = .now,
         isAuthorized: @escaping @MainActor () async -> Bool,
         preferences: @escaping @MainActor () -> BossPreferences) {
        self.center = center
        self.since = since
        self.isAuthorized = isAuthorized
        self.preferences = preferences
    }

    func receive(_ pending: [PendingQuestionnaire]) async {
        let fresh = pending.filter {
            $0.blocking && seen.insert($0.requestId).inserted
                && (ISODate.parse($0.createdAt).map { $0 >= since } ?? true)
        }
        guard !fresh.isEmpty,
              let alert = MessageAlertPolicy.decisionAlert(priority: "normal", preferences: preferences()),
              await isAuthorized() else { return }
        for questionnaire in fresh {
            try? await center.postQuestionnaire(QuestionnaireNotice(questionnaire: questionnaire, alert: alert))
        }
    }
}

extension SystemMessageNotificationCenter: QuestionnaireNotifying {
    func postQuestionnaire(_ notice: QuestionnaireNotice) async throws {
        guard isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.sound = notice.alert.sound ? .default : nil
        content.interruptionLevel = notice.alert.level.interruptionLevel
        content.userInfo = [QuestionnaireNotice.userInfoKey: notice.panelID]
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "questionnaire-" + notice.requestID, content: content, trigger: nil
        ))
    }
}
