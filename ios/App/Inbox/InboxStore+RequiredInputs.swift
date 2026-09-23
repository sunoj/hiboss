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

    func startRequiredInputs(_ api: any BossServing) {
        guard let service = api as? any RequiredInputServing else { return }
        requiredEpoch += 1
        let epoch = requiredEpoch
        requiredStreamTask = Task { [weak self] in
            await self?.consumeRequiredInputs(service, epoch: epoch)
        }
    }

    func stopRequiredInputs() {
        requiredEpoch += 1
        cancelRequiredFetch()
        requiredStreamTask?.cancel()
        requiredStreamTask = nil
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
        do {
            let messages = try await service.fetchRequiredInputs()
            guard !Task.isCancelled, epoch == requiredEpoch,
                  version == requiredFetchVersion else { return }
            requiredInputs = messages
            requiredInputError = nil
            requiredInputLoaded = true
            let pending = Set(messages.map(\.id))
            withdrawn.formIntersection(pending)
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
            try? await Task<Never, Never>.sleep(for: reconnectDelay)
        }
    }
}
