// Serializes history sync, debounces stream bursts, and merges snapshots off the main actor.
// Exports HistorySync; only changed arrays reach the native stores through its observer.
// Depends on BossServing; retains account history only in memory with periodic reconciliation.

import Foundation

public actor HistorySync {
    public typealias Observer = @MainActor @Sendable ([HistoryMessage]?, String?) async -> Void
    private let api: any BossServing
    private let limit: Int
    private let debounce: Duration
    private let fullInterval: TimeInterval
    private let observer: Observer
    private let now: @Sendable () -> Date
    private var messages: [HistoryMessage] = []
    private var cursor: String?
    private var fullFetchedAt: Date?
    private var stopped = false
    private var pending = false
    private var pendingFull = false
    private var worker: Task<Void, Never>?
    private var timer: Task<Void, Never>?

    public init(
        api: any BossServing,
        limit: Int = AppConstants.API.historyLimit, debounce: Duration = .milliseconds(250),
        fullInterval: TimeInterval = 15 * 60, now: @escaping @Sendable () -> Date = { Date() },
        observer: @escaping Observer
    ) {
        self.api = api
        self.now = now
        self.limit = limit
        self.debounce = debounce
        self.fullInterval = fullInterval
        self.observer = observer
    }

    public func synchronize(forceFull: Bool = false, debounced: Bool = false) async {
        request(forceFull: forceFull, debounced: debounced)
        await worker?.value
    }

    public func request(forceFull: Bool = false, debounced: Bool = true) {
        guard !stopped else { return }
        pending = true
        pendingFull = pendingFull || forceFull
        if worker == nil {
            worker = Task { await self.drain(debounced: debounced) }
        }
    }

    public func stop() {
        stopped = true
        worker?.cancel()
        timer?.cancel()
        worker = nil
        timer = nil
    }

    private func drain(debounced: Bool) async {
        if debounced { try? await Task.sleep(for: debounce) }
        guard !stopped, !Task.isCancelled else { return }
        startTimer()
        while pending && !stopped && !Task.isCancelled {
            let forceFull = pendingFull
            pending = false
            pendingFull = false
            do {
                try await fetch(forceFull: forceFull)
            } catch {
                if !stopped && !Task.isCancelled { await observer(nil, error.localizedDescription) }
            }
        }
        worker = nil
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Task { [weak self, fullInterval] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(fullInterval)) } catch { return }
                await self?.synchronize(forceFull: true)
            }
        }
    }

    private func fetch(forceFull: Bool) async throws {
        let due = fullFetchedAt.map { now().timeIntervalSince($0) >= fullInterval } ?? true
        let cursor = forceFull || due ? nil : self.cursor
        var page = try await api.fetchHistoryPage(updatedAfter: cursor)
        var replacement = cursor == nil || page.cursor == nil
        if cursor != nil && page.hasMore == true {
            page = try await api.fetchHistoryPage(updatedAfter: nil)
            replacement = true
        }
        guard !stopped, !Task.isCancelled else { return }
        let merged = Self.merge(replacement ? [] : messages, with: page.messages, limit: limit)
        let changed = merged != messages
        messages = merged
        self.cursor = page.cursor
        if replacement { fullFetchedAt = now() }
        await observer(changed ? merged : nil, nil)
    }

    static func merge(
        _ existing: [HistoryMessage], with updates: [HistoryMessage], limit: Int
    ) -> [HistoryMessage] {
        var rows: [MessageID: HistoryMessage] = [:]
        for row in existing { rows[row.id] = row }
        for row in updates { rows[row.id] = row }
        let dated = rows.values.map { (row: $0, date: ISODate.parse($0.createdAt) ?? .distantPast) }
        return dated.sorted {
            $0.date == $1.date ? $0.row.id.rawValue < $1.row.id.rawValue : $0.date > $1.date
        }.prefix(max(0, limit)).map(\.row)
    }
}
