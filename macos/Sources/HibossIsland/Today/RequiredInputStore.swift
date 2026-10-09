// Maintains the server's complete open-decision list independently of bounded history.
// Exports: RequiredInputStore and atomic RequiredInputState coverage evidence.
// Dependencies: Combine, Foundation, and HibossKit RequiredInputServing.

import Combine
import Foundation
import HibossKit

struct RequiredInputState: Equatable {
    var messages: [HistoryMessage] = []
    var ready = false
    var loaded = false
    var failed = false

    var coverageComplete: Bool { ready && loaded && !failed }
}

@MainActor
final class RequiredInputStore: ObservableObject {
    @Published private(set) var state = RequiredInputState()
    private var service: (any RequiredInputServing)?
    private var streamTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var epoch = 0
    private var fetchVersion = 0
    private let reconnectDelay: Duration

    init(reconnectDelay: Duration = AppConstants.API.reconnectDelay) {
        self.reconnectDelay = reconnectDelay
    }

    deinit {
        streamTask?.cancel()
        fetchTask?.cancel()
    }

    func connect(_ service: any RequiredInputServing) {
        disconnect()
        self.service = service
        startStream(service)
    }

    private func startStream(_ service: any RequiredInputServing) {
        epoch += 1
        streamTask?.cancel()
        invalidateFetch()
        state.ready = false
        state.failed = false
        let epoch = epoch
        streamTask = Task { [weak self] in
            await self?.consume(service, epoch: epoch)
        }
    }

    func disconnect() {
        epoch += 1
        invalidateFetch()
        streamTask?.cancel()
        streamTask = nil
        service = nil
        state = RequiredInputState()
    }

    func refresh() {
        guard let service else { return }
        guard state.ready else {
            startStream(service)
            return
        }
        invalidateFetch()
        let epoch = epoch
        let version = fetchVersion
        fetchTask = Task { [weak self] in
            do {
                let messages = try await service.fetchRequiredInputs()
                guard let self, !Task.isCancelled, self.epoch == epoch,
                      self.fetchVersion == version else { return }
                self.state = RequiredInputState(messages: messages, ready: self.state.ready, loaded: true)
            } catch {
                guard let self, !Task.isCancelled, self.epoch == epoch,
                      self.fetchVersion == version else { return }
                self.state.failed = true
            }
        }
    }

    private func invalidateFetch() {
        fetchVersion += 1
        fetchTask?.cancel()
        fetchTask = nil
        state.loaded = false
    }

    private func apply(_ event: RequiredInputEvent) {
        invalidateFetch()
        switch event {
        case .ready:
            state.ready = true
        case let .message(message):
            state.messages.removeAll { $0.id == message.id }
            state.messages.append(message)
        case let .resolved(id):
            state.messages.removeAll { $0.id == id }
        }
        if state.ready { refresh() }
    }

    private func consume(_ service: any RequiredInputServing, epoch: Int) async {
        while !Task.isCancelled, self.epoch == epoch {
            invalidateFetch()
            state.ready = false
            let stream = await service.requiredInputStream()
            guard !Task.isCancelled, self.epoch == epoch else { return }
            do {
                for try await event in stream {
                    guard !Task.isCancelled, self.epoch == epoch else { return }
                    apply(event)
                }
            } catch {
                guard !Task.isCancelled, self.epoch == epoch else { return }
                state.failed = true
            }
            guard !Task.isCancelled, self.epoch == epoch else { return }
            invalidateFetch()
            state.ready = false
            do { try await Task.sleep(for: reconnectDelay) }
            catch { return }
        }
    }
}
