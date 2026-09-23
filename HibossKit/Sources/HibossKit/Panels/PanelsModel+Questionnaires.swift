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
        invalidateQuestionnaireCoverage()
        if isFetching { needsReconcile = true }
        let generation = questionnaireGeneration
        do {
            let service = try await panelService()
            guard generation == questionnaireGeneration else { return }
            if let relayConfig { startWallSubscription(config: relayConfig) }
            await refreshPendingQuestionnaires(using: service as? any QuestionnaireServing)
        } catch {
            guard generation == questionnaireGeneration else { return }
            questionnaireError = error.localizedDescription
        }
    }

    func refreshPendingQuestionnaires(using service: (any QuestionnaireServing)?) async {
        guard !isDemoMode else { return }
        invalidateQuestionnaireCoverage()
        guard !isLoadingQuestions else { needsReconcile = true; return }
        guard let service else { return }
        let generation = questionnaireGeneration
        isLoadingQuestions = true
        defer {
            isLoadingQuestions = false
            if needsReconcile, !isFetching { needsReconcile = false; reconcileSoon() }
        }
        do {
            let fetched = try await service.fetchPendingQuestionnaires()
            try Task.checkCancellation()
            guard generation == questionnaireGeneration else { return }
            pendingQuestionnaires = fetched
            questionnaireError = nil
            hasCompleteQuestionnaires = (wallConnection == nil || isWallConnected)
                && !needsReconcile && reconciliationTask == nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == questionnaireGeneration else { return }
            if (error as? HibossAPIError)?.isAuthFailure == true { pendingQuestionnaires = [] }
            questionnaireError = error.localizedDescription
        }
    }

    func invalidateQuestionnaireCoverage() {
        questionnaireGeneration &+= 1
        hasCompleteQuestionnaires = false
    }
}
