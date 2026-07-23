// Inbox view model: a live list of pending decisions plus full history.
// Exports: InboxStore driving the Inbox screen (stream + history + reply).
// Dependencies: HibossKit BossServing/HibossAPI and the message display helpers.

import Combine
import Foundation
import HibossKit

@MainActor
final class InboxStore: ObservableObject {
    @Published private(set) var history: [HistoryMessage] = []
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var loadError: String?
    /// Ids removed optimistically (answered/expired locally) until history catches up.
    @Published private(set) var withdrawn: Set<MessageID> = []

    private var api: (any BossServing)?
    private let reconnectDelay: Duration
    private var streamTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?

    init(reconnectDelay: Duration = AppConstants.API.reconnectDelay) {
        self.reconnectDelay = reconnectDelay
    }

    /// Pending decisions, most urgent first, then newest.
    var pending: [HistoryMessage] {
        history
            .filter { $0.isPendingDecision && !withdrawn.contains($0.id) }
            .sorted {
                let l = $0.priorityValue.rank, r = $1.priorityValue.rank
                return l == r ? $0.createdAt > $1.createdAt : l > r
            }
    }

    var pendingCount: Int { pending.count }

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
        api = nil
        history = []
        withdrawn = []
        connectionState = .disconnected
    }

    func refreshHistory() {
        guard let api else { return }
        historyTask?.cancel()
        historyTask = Task { [weak self] in
            do {
                let messages = try await api.fetchHistory()
                guard !Task.isCancelled, let self else { return }
                self.history = messages
                self.loadError = nil
                self.pruneWithdrawn()
                await DecisionActivityManager.sync(pending: self.pending)
            } catch where Task.isCancelled {
                return
            } catch {
                self?.loadError = error.localizedDescription
            }
        }
    }

    /// Awaitable history reload for pull-to-refresh; keeps the spinner up until done.
    func refresh() async {
        guard let api else { return }
        do {
            let messages = try await api.fetchHistory()
            history = messages
            loadError = nil
            pruneWithdrawn()
            await DecisionActivityManager.sync(pending: pending)
        } catch {
            loadError = error.localizedDescription
        }
    }

    @discardableResult
    func reply(_ choice: String, to id: MessageID) async -> Bool {
        guard let api else { return false }
        withdrawn.insert(id)
        do {
            _ = try await api.reply(to: id, with: choice)
            refreshHistory()
            return true
        } catch {
            withdrawn.remove(id)
            loadError = error.localizedDescription
            return false
        }
    }

    private func consume(_ api: any BossServing) async {
        while !Task.isCancelled {
            connectionState = .connecting
            let stream = await api.messageStream()
            connectionState = .connected
            do {
                for try await event in stream {
                    handle(event)
                }
            } catch where !Task.isCancelled {
                connectionState = .failed(error.localizedDescription)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            try? await Task<Never, Never>.sleep(for: reconnectDelay)
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
}
