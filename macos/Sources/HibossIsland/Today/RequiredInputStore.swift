// Maintains the server's complete open-decision list independently of bounded history.
// Exports: RequiredInputStore and atomic RequiredInputState coverage evidence.
// Dependencies: Combine, Foundation, and HibossKit RequiredInputServing.

import Combine
import Foundation
import HibossKit
import OSLog

struct RequiredInputState: Equatable {
    var messages: [HistoryMessage] = []
    var ready = false
    var loaded = false // Retained for at most 30 seconds while the stream is down.
    var failed = false
    var refreshing = false
    var listingVersion = 0
    var listedIDs: Set<MessageID> = []

    var coverageComplete: Bool { ready && loaded && !failed }
}

@MainActor
final class RequiredInputStore: ObservableObject {
    private static let log = Logger(subsystem: "ai.hiboss.island", category: "required-inputs")
    @Published private(set) var state = RequiredInputState() {
        didSet {
            guard oldValue.ready != state.ready || oldValue.loaded != state.loaded
                || oldValue.failed != state.failed else { return }
            let summary = "ready=\(state.ready) loaded=\(state.loaded) failed=\(state.failed)"
                + " count=\(state.messages.count)"
            Self.log.info("required-input state \(summary, privacy: .public)")
        }
    }
    private var service: (any RequiredInputServing)?
    private var streamTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var staleTask: Task<Void, Never>?
    private var epoch = 0
    private var fetchVersion = 0
    private var retryAttempt = 0
    /// Stream changes seen while a fetch is in flight, re-applied over its older result.
    private var resolvedDuringFetch: Set<MessageID> = []
    private var updatedDuringFetch: [HistoryMessage] = []
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
        retryTask?.cancel()
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
        retryAttempt = 0
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
        resolvedDuringFetch = []
        updatedDuringFetch = []
        let epoch = epoch
        let version = fetchVersion
        fetchTask = Task { [weak self] in
            do {
                let messages = try await service.fetchRequiredInputs()
                guard let self, !Task.isCancelled, self.epoch == epoch,
                      self.fetchVersion == version else { return }
                let reconciled = self.reconcile(messages)
                self.state = RequiredInputState(messages: reconciled, ready: self.state.ready,
                    loaded: true, listingVersion: self.state.listingVersion + 1,
                    listedIDs: Set(reconciled.map(\.id)))
                self.fetchTask = nil
                self.retryAttempt = 0
                self.cancelStaleDeadline()
                if !self.state.ready { self.scheduleStaleDeadline() }
            } catch {
                guard let self, !Task.isCancelled, self.epoch == epoch,
                      self.fetchVersion == version else { return }
                Self.log.error("required-input fetch failed: \(String(describing: error), privacy: .public)")
                self.state.failed = true
                self.state.refreshing = false
                self.fetchTask = nil
                self.retryFetch(epoch: epoch, version: version)
            }
        }
    }

    private func retryFetch(epoch: Int, version: Int) {
        guard state.ready else { return }
        let delay = Duration.seconds(min(5, 1 << min(retryAttempt, 3)))
        retryAttempt = min(retryAttempt + 1, 3)
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) }
            catch { return }
            guard let self, !Task.isCancelled, self.state.ready,
                  self.epoch == epoch, self.fetchVersion == version else { return }
            self.refresh()
        }
    }

    private func reconcile(_ fetched: [HistoryMessage]) -> [HistoryMessage] {
        var result = fetched.filter { !resolvedDuringFetch.contains($0.id) }
        for message in updatedDuringFetch {
            result.removeAll { $0.id == message.id }
            result.append(message)
        }
        resolvedDuringFetch = []
        updatedDuringFetch = []
        return result
    }

    private func invalidateFetch() {
        fetchVersion += 1
        fetchTask?.cancel()
        fetchTask = nil
        retryTask?.cancel()
        retryTask = nil
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

    /// Only `ready` starts the list fetch. Ordinary events update the list in place and never
    /// cancel a fetch: the stream polls every few seconds, and on a slow link a fetch restarted
    /// by each event never finished, so the list stayed "Loading" while the stream was live.
    private func apply(_ event: RequiredInputEvent) {
        switch event {
        case .ready:
            cancelStaleDeadline()
            state.ready = true
            if fetchTask == nil { refresh() }
        case let .message(message):
            var next = state
            next.messages.removeAll { $0.id == message.id }
            next.messages.append(message)
            next.listingVersion += 1
            next.listedIDs = [message.id]
            state = next
            if fetchTask != nil {
                updatedDuringFetch.removeAll { $0.id == message.id }
                updatedDuringFetch.append(message)
                resolvedDuringFetch.remove(message.id)
            }
        case let .resolved(id):
            state.messages.removeAll { $0.id == id }
            if fetchTask != nil {
                resolvedDuringFetch.insert(id)
                updatedDuringFetch.removeAll { $0.id == id }
            }
        }
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
                Self.log.error("required-input stream ended: \(String(describing: error), privacy: .public)")
                guard !Task.isCancelled, self.epoch == epoch else { return }
                // Transport errors and EOF share the same bounded stale-list authority.
            }
            guard !Task.isCancelled, self.epoch == epoch else { return }
            state.ready = false
            scheduleStaleDeadline()
            do { try await Task.sleep(for: reconnectDelay) }
            catch { return }
        }
    }
}
