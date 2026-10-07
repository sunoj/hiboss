// Complete Home input coverage and reconnect reconciliation for InboxStore.
// Exports required-input lifecycle helpers; depends on RequiredInputServing.
// Keeps bounded Inbox history independent of the authoritative Home set.

import Foundation
import HibossKit

@MainActor
extension InboxStore {
    var hasCompleteRequiredInputs: Bool {
        requiredInputReady && requiredInputLoaded && requiredInputError == nil
    }

    func retryRequiredInputConnection() {
        guard let api else { return }
        requiredStreamTask?.cancel()
        cancelRequiredFetch()
        startRequiredInputs(api)
    }

    func startRequiredInputs(_ api: any BossServing) {
        guard let service = api as? any RequiredInputServing else {
            requiredInputError = String(localized: "Requests are unavailable on this connection.")
            return
        }
        requiredEpoch += 1
        let epoch = requiredEpoch
        watchRequiredInputCoverage()
        requiredStreamTask = Task { [weak self] in
            await self?.consumeRequiredInputs(service, epoch: epoch)
        }
    }

    func stopRequiredInputs() {
        requiredEpoch += 1
        cancelRequiredFetch()
        requiredStreamTask?.cancel()
        requiredStreamTask = nil
        requiredCoverageTask?.cancel()
        requiredCoverageTask = nil
        requiredInputs = []
        requiredInputReady = false
        requiredInputLoaded = false
        requiredInputError = nil
    }

    func refreshRequiredInputs() async {
        guard !Task.isCancelled else { return }
        guard let service = api as? any RequiredInputServing else { return }
        let epoch = requiredEpoch
        requiredFetchVersion += 1
        let version = requiredFetchVersion
        requiredInputLoaded = false
        watchRequiredInputCoverage()
        do {
            let messages = try await service.fetchRequiredInputs()
            guard !Task.isCancelled, epoch == requiredEpoch,
                  version == requiredFetchVersion else { return }
            requiredInputs = messages
            if requiredInputReady {
                requiredInputError = nil
                requiredCoverageTask?.cancel()
                requiredCoverageTask = nil
            }
            requiredInputLoaded = true
            let pending = Set(messages.map(\.id))
            withdrawn.formIntersection(pending)
            await syncDecisionActivity()
        } catch {
            guard !Task.isCancelled, epoch == requiredEpoch,
                  version == requiredFetchVersion else { return }
            requiredInputError = error.localizedDescription
            requiredInputLoaded = false
        }
    }

    func cancelRequiredFetch() {
        requiredFetchVersion += 1
        requiredInputLoaded = false
        requiredFetchTask?.cancel()
        requiredFetchTask = nil
        watchRequiredInputCoverage()
    }

    private func reconcileRequiredInputs() {
        requiredFetchTask = Task { [weak self] in
            await self?.refreshRequiredInputs()
        }
    }

    private func applyRequiredInputEvent(_ event: RequiredInputEvent) {
        cancelRequiredFetch()
        switch event {
        case .ready:
            requiredInputReady = true
        case let .message(message):
            requiredInputs.removeAll { $0.id == message.id }
            requiredInputs.append(message)
        case let .resolved(id):
            requiredInputs.removeAll { $0.id == id }
        }
        if requiredInputReady { reconcileRequiredInputs() }
    }

    private func consumeRequiredInputs(_ service: any RequiredInputServing, epoch: Int) async {
        while !Task.isCancelled, epoch == requiredEpoch {
            cancelRequiredFetch()
            requiredInputReady = false
            requiredInputLoaded = false
            let stream = await service.requiredInputStream()
            guard !Task.isCancelled, epoch == requiredEpoch else { return }
            do {
                for try await event in stream {
                    guard !Task.isCancelled, epoch == requiredEpoch else { return }
                    applyRequiredInputEvent(event)
                }
            } catch {
                guard !Task.isCancelled, epoch == requiredEpoch else { return }
                requiredInputError = error.localizedDescription
            }
            guard !Task.isCancelled, epoch == requiredEpoch else { return }
            cancelRequiredFetch()
            requiredInputReady = false
            requiredInputLoaded = false
            // The server rotates this stream every few minutes; a clean end is routine. The
            // coverage watchdog escalates only if the reconnect does not restore coverage.
            try? await Task<Never, Never>.sleep(for: reconnectDelay)
        }
    }

    private func watchRequiredInputCoverage() {
        guard requiredCoverageTask == nil else { return }
        requiredCoverageTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) }
            catch { return }
            guard let self, !self.hasCompleteRequiredInputs else { return }
            self.requiredInputError = self.requiredInputReady
                ? String(localized: "Requests are still loading. Retry to check for unanswered requests.")
                : String(localized: "Requests connection is not ready. Retry to reconnect.")
        }
    }
}
