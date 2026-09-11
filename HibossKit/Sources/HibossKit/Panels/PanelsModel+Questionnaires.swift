// Discovers unanswered questionnaires independently of wall placement and visibility.
// Exports pending counts and refresh behavior for both native panel clients.
// Dependencies: QuestionnaireServing, panel lifecycle, and anchored server clocks.

import Foundation

extension PanelsModel {
    public var pendingQuestionnaireCount: Int { tiles.reduce(0) { $0 + pendingCount(for: $1) } }

    public func pendingCount(for tile: PanelTile) -> Int {
        guard !tile.lifecycle.taskState.isTerminal else { return 0 }
        let reference = serverNow(for: tile.id)
        return pendingQuestionnaires.filter {
            $0.panelId == tile.id && (panelDate($0.expiresAt).map { $0 > reference } ?? true)
        }.count
    }

    public func refreshPendingQuestionnaires() async {
        do { await refreshPendingQuestionnaires(using: try await panelService() as? any QuestionnaireServing) }
        catch { questionnaireError = error.localizedDescription }
    }

    func refreshPendingQuestionnaires(using service: (any QuestionnaireServing)?) async {
        guard !isDemoMode, !isLoadingQuestions, let service else { return }
        isLoadingQuestions = true
        defer { isLoadingQuestions = false }
        do {
            let fetched = try await service.fetchPendingQuestionnaires()
            try Task.checkCancellation()
            pendingQuestionnaires = fetched
            questionnaireError = nil
        } catch is CancellationError {
            return
        } catch {
            if (error as? HibossAPIError)?.isAuthFailure == true { pendingQuestionnaires = [] }
            questionnaireError = error.localizedDescription
        }
    }
}
