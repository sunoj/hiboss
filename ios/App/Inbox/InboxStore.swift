// Inbox view model: a live list of pending decisions plus full history.
// Exports: InboxStore driving the Inbox screen (stream + history + reply).
// Dependencies: HibossKit BossServing/HibossAPI and the message display helpers.

import Combine
import Foundation
import HibossKit

/// Outcome of submitting a boss reply, so callers can tell a real send apart
/// from a decision that was already resolved elsewhere or a transport failure.
enum ReplyResult: Equatable { case sent, alreadyResolved, failed }

@MainActor
final class InboxStore: ObservableObject {
    @Published private(set) var history: [HistoryMessage] = []
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var loadError: String?
    /// False until the first history fetch completes, so views can show a spinner
    /// instead of flashing an empty state on cold launch.
    @Published private(set) var didLoad = false
    /// Ids removed optimistically (answered/expired locally) until history catches up.
    @Published private(set) var withdrawn: Set<MessageID> = []

    private var api: (any BossServing)?
    private let reconnectDelay: Duration
    private var streamTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    /// One timer per pending decision deadline, so an expiring card drops out of
    /// `pending` on time instead of waiting for the next unrelated stream event.
    private var expiryTasks: [MessageID: Task<Void, Never>] = [:]
    private var decisionAlertsEnabled: Bool

    init(
        reconnectDelay: Duration = AppConstants.API.reconnectDelay,
        decisionAlertsEnabled: Bool = true
    ) {
        self.reconnectDelay = reconnectDelay
        self.decisionAlertsEnabled = decisionAlertsEnabled
    }

    /// Pending decisions, soonest-to-expire first, then critical > high > normal.
    var pending: [HistoryMessage] {
        history
            .filter { $0.isPendingDecision && !withdrawn.contains($0.id) }
            .sorted(by: Self.moreUrgent)
    }

    var pendingCount: Int { pending.count }

    /// Settled history for the Messages-style list, newest first. Live pending
    /// cards are excluded so a decision isn't shown twice.
    var settledHistory: [HistoryMessage] {
        let live = Set(pending.map(\.id))
        return history
            .filter { !live.contains($0.id) }
            .sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
    }

    /// Soonest deadline first (none last), then higher priority, then newest.
    private static func moreUrgent(_ lhs: HistoryMessage, _ rhs: HistoryMessage) -> Bool {
        switch (lhs.expirationDate, rhs.expirationDate) {
        case let (a?, b?) where a != b:
            return a < b
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            break
        }
        let left = lhs.priorityValue.rank, right = rhs.priorityValue.rank
        if left != right { return left > right }
        return (lhs.createdDate ?? .distantPast) > (rhs.createdDate ?? .distantPast)
    }

    /// True once a backing API is attached (i.e. `start` has run). Deep-linked
    /// detail views poll this to avoid declaring a message missing during the
    /// cold-launch window before the store is connected.
    var isReady: Bool { api != nil }

    func setDecisionAlertsEnabled(_ enabled: Bool) {
        guard decisionAlertsEnabled != enabled else { return }
        decisionAlertsEnabled = enabled
        Task { await syncDecisionActivity() }
    }

    func syncDecisionActivity() async {
        await DecisionActivityManager.sync(pending: pending, alertsEnabled: decisionAlertsEnabled)
    }

    func start(api: any BossServing) {
        stop()
        self.api = api
        connectionState = .connecting
        streamTask = Task { [weak self] in await self?.consume(api) }
        refreshHistory()
    }

    func stop() {
        streamTask?.cancel()
        historyTask?.cancel()
        streamTask = nil
        historyTask = nil
        cancelExpiries()
        api = nil
        history = []
        withdrawn = []
        didLoad = false
        loadError = nil
        connectionState = .disconnected
    }

    func refreshHistory() {
        guard let api else { return }
        historyTask?.cancel()
        historyTask = Task { [weak self] in
            do {
                let messages = try await api.fetchHistory()
                guard !Task.isCancelled, let self else { return }
                self.applyHistory(messages)
                await self.syncDecisionActivity()
            } catch where Task.isCancelled {
                return
            } catch {
                self?.loadError = error.localizedDescription
                self?.didLoad = true
            }
        }
    }

    /// Awaitable history reload for pull-to-refresh; keeps the spinner up until done.
    func refresh() async {
        guard let api else { return }
        do {
            let messages = try await api.fetchHistory()
            applyHistory(messages)
            await syncDecisionActivity()
        } catch {
            loadError = error.localizedDescription
            didLoad = true
        }
    }

    /// Commit a fresh history snapshot and re-arm all derived state.
    private func applyHistory(_ messages: [HistoryMessage]) {
        history = messages
        loadError = nil
        didLoad = true
        pruneWithdrawn()
        rescheduleExpiries()
    }

    @discardableResult
    func reply(_ choice: String, to id: MessageID) async -> ReplyResult {
        guard let api else { return .failed }
        withdrawn.insert(id)
        do {
            let outcome = try await api.reply(to: id, with: choice)
            refreshHistory()
            return outcome == .alreadyResolved ? .alreadyResolved : .sent
        } catch {
            withdrawn.remove(id)
            loadError = error.localizedDescription
            return .failed
        }
    }

    private func consume(_ api: any BossServing) async {
        var failures = 0
        while !Task.isCancelled {
            connectionState = .connecting
            let stream = await api.messageStream()
            connectionState = .connected
            do {
                for try await event in stream {
                    failures = 0            // a live stream delivering data
                    handle(event)
                }
            } catch where !Task.isCancelled {
                if (error as? HibossAPIError)?.isAuthFailure == true {
                    // A rejected token won't fix itself — stop reconnecting and
                    // surface it instead of retrying forever every few seconds.
                    connectionState = .failed("Session expired — reconnect in Settings.")
                    return
                }
                connectionState = .failed(error.localizedDescription)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            failures += 1
            // Capped exponential backoff so a persistent outage doesn't hammer
            // the server / drain the battery at a fixed cadence.
            let backoff = min(reconnectDelay * (1 << min(failures, 5)), .seconds(60))
            try? await Task<Never, Never>.sleep(for: backoff)
        }
    }

    private func handle(_ event: BossEvent) {
        switch event {
        case .message:
            refreshHistory()
        case let .resolved(resolution):
            withdrawn.insert(resolution.id)
            refreshHistory()
        }
    }

    /// Drop withdrawn ids once history no longer lists them as pending.
    private func pruneWithdrawn() {
        let stillPending = Set(history.filter(\.isPendingDecision).map(\.id))
        withdrawn.formIntersection(stillPending)
    }

    /// Arm one timer per pending deadline; when it fires, republish so `pending`
    /// recomputes and the now-expired decision drops to a read-only state.
    private func rescheduleExpiries() {
        cancelExpiries()
        for message in history where message.isPendingDecision {
            guard let deadline = message.expirationDate else { continue }
            let delay = deadline.timeIntervalSinceNow
            guard delay > 0 else { continue }
            let id = message.id
            expiryTasks[id] = Task { [weak self] in
                try? await Task<Never, Never>.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.expiryTasks[id] = nil
                self.objectWillChange.send()
                await self.syncDecisionActivity()
            }
        }
    }

    private func cancelExpiries() {
        for task in expiryTasks.values { task.cancel() }
        expiryTasks.removeAll()
    }
}
