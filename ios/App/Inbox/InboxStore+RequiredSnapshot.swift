// Reconciles complete input snapshots with newer stream events and retries failed reads.
// Exports InboxStore snapshot helpers; deadlines and coverage remain in RequiredInputs.
// Dependencies: Foundation, HibossKit, and the store's connection epoch.

import Foundation
import HibossKit

@MainActor
extension InboxStore {
    func reconcileRequiredSnapshot(_ messages: [HistoryMessage]) -> [HistoryMessage] {
        var result = messages.filter { !requiredFetchResolutions.contains($0.id) }
        for message in requiredFetchUpdates.values {
            result.removeAll { $0.id == message.id }
            result.append(message)
        }
        requiredFetchUpdates = [:]
        requiredFetchResolutions = []
        return result
    }

    func retryRequiredSnapshot(epoch: Int, version: Int) {
        guard requiredInputReady else { return }
        let delay = Duration.seconds(min(5, 1 << min(requiredRetryAttempt, 3)))
        requiredRetryAttempt = min(requiredRetryAttempt + 1, 3)
        requiredRetryTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) }
            catch { return }
            guard let self, !Task.isCancelled, self.requiredInputReady,
                  self.requiredEpoch == epoch, self.requiredFetchVersion == version else { return }
            self.requiredRetryTask = nil
            self.reconcileRequiredInputs()
        }
    }
}
