// Owns panels and questionnaires for the app's lifetime, not the main window's.
// Exports: AppDelegate.observePanels (coverage, account changes, questionnaire notifications).
// Dependencies: Combine, HibossKit PanelsModel, OverviewStore, and QuestionnaireNotifier.

import Combine
import Foundation
import HibossKit

extension AppDelegate {
    /// With the main window closed a blocking questionnaire is still fetched, holds back the
    /// all-clear, and is announced; the window only renders this model.
    func observePanels() {
        let notifier = QuestionnaireNotifier(center: notificationCenter, isAuthorized: { [notifications] in
            await notifications.prepareAuthorization()
            return notifications.authorization == .authorized || notifications.authorization == .provisional
        }, preferences: { [preferencesStore] in preferencesStore.preferences })
        panels.$pendingQuestionnaires
            .sink { pending in Task { await notifier.receive(pending) } }
            .store(in: &cancellables)
        panels.objectWillChange
            .receive(on: RunLoop.main)
            .map { [panels] _ in panels.hasDisplayCoverage && !panels.pendingQuestionnaires.contains(where: \.blocking) }
            .removeDuplicates()
            .sink { [overview] in overview.setQuestionnaireCoverage($0) }
            .store(in: &cancellables)
        settings.$activeClientConfig
            .removeDuplicates()
            .dropFirst()
            .sink { [panels] _ in
                panels.connectionDidChange()
                Task { await panels.load() }
            }
            .store(in: &cancellables)
        notificationCenter.onOpenQuestionnaire = { [weak self] panelID in
            self?.notificationNavigation.openMainWindow()
            Task { [weak self] in _ = await self?.panels.openWhenLoaded(panelID) }
        }
    }
}
