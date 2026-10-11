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

    func refreshPendingQuestionnaires(
        using service: (any QuestionnaireServing)?, generation: UInt64? = nil
    ) async {
        guard !isDemoMode else { return }
        if generation == nil { invalidateQuestionnaireCoverage() }
        guard !isLoadingQuestions else {
            if generation != activeQuestionnaireGeneration { needsReconcile = true }
            return
        }
        guard let service else { return }
        let generation = generation ?? questionnaireGeneration
        activeQuestionnaireGeneration = generation
        isLoadingQuestions = true
        let wallWasConnected = isWallConnected
        #if os(iOS)
        questionnaireOperation += 1
        let operation = questionnaireOperation
        #endif
        defer {
            #if os(iOS)
            if operation == questionnaireOperation { finishQuestionnaireFetch() }
            #else
            finishQuestionnaireFetch()
            #endif
        }
        do {
            var fetched = try await service.fetchPendingQuestionnaires()
            if wallConnection != nil, !wallWasConnected, isWallConnected,
               generation == questionnaireGeneration {
                fetched = try await service.fetchPendingQuestionnaires()
            }
            try Task.checkCancellation()
            guard generation == questionnaireGeneration else { return }
            installQuestionnaires(fetched)
        } catch is CancellationError {
            return
        } catch {
            guard generation == questionnaireGeneration else { return }
            if (error as? HibossAPIError)?.isAuthFailure == true { pendingQuestionnaires = [] }
            questionnaireError = error.localizedDescription
        }
    }

    private func installQuestionnaires(_ fetched: [PendingQuestionnaire]) {
        pendingQuestionnaires = fetched
        questionnaireError = nil
        hasCompleteQuestionnaires = (wallConnection == nil || isWallConnected)
            && !needsReconcile && reconciliationTask == nil
        if hasCompleteQuestionnaires {
            StartupLog.record("questionnaires complete", count: fetched.count)
        }
    }

    private func finishQuestionnaireFetch() {
        isLoadingQuestions = false
        activeQuestionnaireGeneration = nil
        if needsReconcile, !isFetching { needsReconcile = false; reconcileSoon() }
    }

    func invalidateQuestionnaireCoverage() {
        questionnaireGeneration &+= 1
        hasCompleteQuestionnaires = false
    }
}
