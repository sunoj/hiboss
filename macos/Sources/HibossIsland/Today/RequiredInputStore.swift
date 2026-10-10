// Maintains the server's complete open-decision list independently of bounded history.
// Exports: RequiredInputStore and atomic RequiredInputState coverage evidence.
// Dependencies: Combine, Foundation, and HibossKit RequiredInputServing.

import Combine
import Foundation
import HibossKit

struct RequiredInputState: Equatable {
    var messages: [HistoryMessage] = []
    var ready = false
    var loaded = false // Retained for at most 30 seconds while the stream is down.
    var failed = false
    var refreshing = false

    var coverageComplete: Bool { ready && loaded && !failed }
}

@MainActor
final class RequiredInputStore: ObservableObject {
    @Published private(set) var state = RequiredInputState()
    private var service: (any RequiredInputServing)?
    private var streamTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var staleTask: Task<Void, Never>?
    private var epoch = 0
    private var fetchVersion = 0
    private let reconnectDelay: Duration
    private let staleListDelay: Duration

    init(reconnectDelay: Duration = AppConstants.API.reconnectDelay,
         staleListDelay: Duration = .seconds(30)) {
        self.reconnectDelay = reconnectDelay
        self.staleListDelay = staleListDelay
    }

    deinit {
        streamTask?.cancel()
        fetchTask?.cancel()
        staleTask?.cancel()
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
        cancelStaleDeadline()
        state = RequiredInputState()
    }

    func refresh() {
        guard let service else { return }
        invalidateFetch()
        state.refreshing = true
        let epoch = epoch
        let version = fetchVersion
        fetchTask = Task { [weak self] in
            do {
                let messages = try await service.fetchRequiredInputs()
                guard let self, !Task.isCancelled, self.epoch == epoch,
                      self.fetchVersion == version else { return }
                self.state = RequiredInputState(messages: messages, ready: self.state.ready, loaded: true)
                self.cancelStaleDeadline()
                if !self.state.ready { self.scheduleStaleDeadline() }
            } catch {
                guard let self, !Task.isCancelled, self.epoch == epoch,
                      self.fetchVersion == version else { return }
                self.state.failed = true
                self.state.refreshing = false
            }
        }
    }

    private func invalidateFetch() {
        fetchVersion += 1
        fetchTask?.cancel()
        fetchTask = nil
        state.refreshing = false
    }

    private func cancelStaleDeadline() {
        staleTask?.cancel()
        staleTask = nil
    }

    private func scheduleStaleDeadline() {
        guard state.loaded, staleTask == nil else { return }
        let delay = staleListDelay
        staleTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) }
            catch { return }
            guard let self, !Task.isCancelled, !self.state.ready else { return }
            self.state.loaded = false
            self.staleTask = nil
        }
    }

    private func apply(_ event: RequiredInputEvent) {
        invalidateFetch()
        switch event {
        case .ready:
            cancelStaleDeadline()
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
                // Transport errors and EOF share the same bounded stale-list authority.
            }
            guard !Task.isCancelled, self.epoch == epoch else { return }
            invalidateFetch()
            state.ready = false
            scheduleStaleDeadline()
            do { try await Task.sleep(for: reconnectDelay) }
            catch { return }
        }
    }
}
