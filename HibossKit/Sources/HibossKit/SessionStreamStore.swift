// Per-session append-only transcript store: history window, SSE tail, scroll lock.
// Exports: SessionStreamStore for SessionMessagesView and unit tests.
// Dependencies: SessionStreamServing, Combine, AppConstants.

import Combine
import Foundation

@MainActor
public final class SessionStreamStore: ObservableObject {
    @Published public private(set) var events: [SessionEvent] = []
    @Published public private(set) var isFollowingLive = true
    @Published public private(set) var pendingWhileLocked = 0
    @Published public private(set) var needsResyncNotice = false
    @Published public private(set) var isLoading = false
    @Published public private(set) var isBackfilling = false
    @Published public private(set) var hasEarlier = false
    @Published public private(set) var loadError: String?
    @Published public private(set) var connectionState: ConnectionState = .disconnected

    public private(set) var lastAppliedSequence = -1

    public let sessionID: String
    private let pageSize: Int
    private let maxWindow: Int
    private let batchMilliseconds: UInt64
    private let reconnectDelay: Duration

    private var api: (any SessionStreamServing)?
    private var streamTask: Task<Void, Never>?
    private var batchTask: Task<Void, Never>?
    private var pendingBatch: [SessionEvent] = []
    private var knownIDs: Set<String> = []

    public init(
        sessionID: String,
        pageSize: Int = AppConstants.API.historyLimit,
        maxWindow: Int = AppConstants.API.sessionStreamWindow,
        batchMilliseconds: UInt64 = AppConstants.API.sessionStreamBatchMilliseconds,
        reconnectDelay: Duration = AppConstants.API.reconnectDelay
    ) {
        self.sessionID = sessionID
        self.pageSize = pageSize
        self.maxWindow = maxWindow
        self.batchMilliseconds = batchMilliseconds
        self.reconnectDelay = reconnectDelay
    }

    public func start(api: any SessionStreamServing) {
        stop()
        self.api = api
        Task { await reloadWindow(reason: .initial) }
    }

    public func stop() {
        streamTask?.cancel()
        streamTask = nil
        batchTask?.cancel()
        batchTask = nil
        pendingBatch.removeAll()
        connectionState = .disconnected
    }

    public func refresh() async {
        await reloadWindow(reason: .manual)
    }

    public func resumeFromForeground() {
        guard api != nil else { return }
        streamTask?.cancel()
        streamTask = Task { await runStreamLoop() }
    }

    /// Reader dragged away from the live end — stop yanking the viewport.
    public func readerScrolledAway() {
        guard isFollowingLive else { return }
        isFollowingLive = false
    }

    public func jumpToLive() {
        isFollowingLive = true
        pendingWhileLocked = 0
    }

    public func dismissResyncNotice() {
        needsResyncNotice = false
    }

    public func loadEarlier() async {
        guard let api, hasEarlier, !isBackfilling, let oldest = events.first?.sequence else { return }
        isBackfilling = true
        defer { isBackfilling = false }
        let after = max(-1, oldest - pageSize - 1)
        let cursor: Int? = after >= 0 ? after : nil
        do {
            let page = try await api.fetchSessionEvents(
                sessionID: sessionID, after: cursor, limit: pageSize
            )
            if page.resync {
                await reloadWindow(reason: .resync)
                return
            }
            let older = page.events.filter { $0.sequence < oldest && knownIDs.insert($0.id).inserted }
            events = Array((older + events).suffix(maxWindow))
            hasEarlier = older.count >= pageSize || (events.first?.sequence ?? 1) > 1
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Test seam: enqueue events as if they arrived on the live stream.
    public func applyStreamEventsForTesting(_ incoming: [SessionEvent]) {
        enqueue(incoming)
        flushBatch()
    }

    private enum ReloadReason { case initial, resync, manual }

    private func reloadWindow(reason: ReloadReason) async {
        guard let api else { return }
        isLoading = true
        loadError = nil
        if reason == .resync { needsResyncNotice = true }
        defer { isLoading = false }
        do {
            let loaded = try await fetchThroughTail(api: api)
            knownIDs = Set(loaded.map(\.id))
            let window = Array(loaded.suffix(maxWindow))
            events = window
            hasEarlier = loaded.count > window.count || (window.first?.sequence ?? 1) > 1
            lastAppliedSequence = window.last?.sequence ?? -1
            isFollowingLive = true
            pendingWhileLocked = 0
            streamTask?.cancel()
            streamTask = Task { await runStreamLoop() }
        } catch {
            loadError = error.localizedDescription
            connectionState = .failed(error.localizedDescription)
        }
    }

    private func fetchThroughTail(api: any SessionStreamServing) async throws -> [SessionEvent] {
        var after: Int?
        var collected: [SessionEvent] = []
        while true {
            let page = try await api.fetchSessionEvents(
                sessionID: sessionID, after: after, limit: pageSize
            )
            if page.resync {
                after = nil
                collected = []
                continue
            }
            collected.append(contentsOf: page.events)
            if collected.count > maxWindow * 2 {
                collected = Array(collected.suffix(maxWindow))
            }
            guard let next = page.nextAfter, page.events.count >= pageSize else { break }
            after = next
        }
        return collected
    }

    private func runStreamLoop() async {
        guard let api else { return }
        while !Task.isCancelled {
            connectionState = .connecting
            let stream = await api.sessionEventStream(sessionID: sessionID, after: lastAppliedSequence)
            connectionState = .connected
            do {
                for try await frame in stream {
                    if Task.isCancelled { return }
                    switch frame {
                    case .resync:
                        await reloadWindow(reason: .resync)
                        return
                    case let .event(event):
                        enqueue([event])
                    }
                }
            } catch {
                if Task.isCancelled { return }
                if let apiError = error as? HibossAPIError, apiError.isAuthFailure {
                    connectionState = .failed(error.localizedDescription)
                    return
                }
                connectionState = .failed(error.localizedDescription)
            }
            connectionState = .connecting
            try? await Task.sleep(for: reconnectDelay)
        }
    }

    private func enqueue(_ incoming: [SessionEvent]) {
        pendingBatch.append(contentsOf: incoming)
        if batchTask == nil {
            batchTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: (self?.batchMilliseconds ?? 50) * 1_000_000)
                self?.flushBatch()
            }
        }
    }

    private func flushBatch() {
        batchTask = nil
        guard !pendingBatch.isEmpty else { return }
        let batch = pendingBatch
        pendingBatch = []
        var appended = 0
        for event in batch {
            guard event.sequence > lastAppliedSequence else { continue }
            guard knownIDs.insert(event.id).inserted else { continue }
            events.append(event)
            lastAppliedSequence = event.sequence
            appended += 1
        }
        if events.count > maxWindow {
            let dropped = events.count - maxWindow
            events.removeFirst(dropped)
            hasEarlier = true
        }
        if appended > 0, !isFollowingLive {
            pendingWhileLocked += appended
        }
    }
}
