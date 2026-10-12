// Inbox view model: a live list of pending decisions plus full history.
// Exports: InboxStore driving the Inbox screen (stream + history + reply).
// Dependencies: HibossKit BossServing/HibossAPI and the message display helpers.

import Combine
import Foundation
import HibossKit

/// Outcome of submitting a boss reply, so callers can tell a real send apart from a
/// decision already resolved elsewhere, a transport failure, or a reply already in flight.
enum ReplyResult: Equatable { case sent, alreadyResolved, failed, busy }

@MainActor
final class InboxStore: ObservableObject {
    @Published var history: [HistoryMessage] = []
    @Published var requiredInputs: [HistoryMessage] = []
    @Published var requiredInputError: String?
    /// A completed result stays rendered until replacement or an account/authorization boundary.
    @Published var requiredInputLoaded = false
    @Published var requiredInputRefreshing = false
    @Published var requiredInputReady = false
    @Published var requiredNeedsReadyRead = false
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published var loadError: String?
    /// False until the first history fetch completes, so views can show a spinner
    /// instead of flashing an empty state on cold launch.
    @Published var didLoad = false
    var historyCheckedAt: Date?
    @Published var isRefreshing = false
    @Published var replyConfirmation: String?
    @Published var replyFeedback: [MessageID: String] = [:]
    /// Ids removed optimistically (answered/expired locally) until history catches up.
    @Published var withdrawn: Set<MessageID> = []
    /// Decisions that should keep a settled card after leaving `pending`.
    @Published private(set) var settledIDs: Set<MessageID> = []
    /// Optimistic / stream-provided answers until history replies catch up.
    @Published private(set) var localResolutions: [MessageID: DecisionSettlement] = [:]
    /// Targeted responses stay available even when the message is older than the
    /// bounded history page loaded in parallel during a notification cold launch.
    @Published var openedMessages: [MessageID: MessageDetail] = [:]
    /// The one per-decision admission point, shared with notification actions and intents.
    let replyGate: DecisionReplyGate
    private var gateObservation: AnyCancellable?

    var api: (any BossServing)?
    let agentAvatars = AgentAvatarStore()
    let reconnectDelay: Duration
    private var streamTask: Task<Void, Never>?
    var historyTask: Task<Void, Never>?
    var historySync: HistorySync?
    var historyVersion = 0
    var historyRequestsInFlight = 0
    var requiredStreamTask: Task<Void, Never>?
    var requiredFetchTask: Task<Void, Never>?
    var requiredEpoch = 0
    var requiredFetchVersion = 0
    var requiredReconcileScheduled = false
    var requiredFetchUpdates: [MessageID: HistoryMessage] = [:]
    var requiredFetchResolutions: Set<MessageID> = []
    var requiredRetryTask: Task<Void, Never>?
    var requiredRetryAttempt = 0
    var requiredCoverageTask: Task<Void, Never>?
    var requiredStaleTask: Task<Void, Never>?
    /// One timer per pending decision deadline, so an expiring card drops out of
    /// `pending` on time instead of waiting for the next unrelated stream event.
    private var expiryTasks: [MessageID: Task<Void, Never>] = [:]
    private var decisionAlertsEnabled: Bool
    private let decisionActivitySync: @MainActor ([HistoryMessage], Bool) async -> Void

    init(
        reconnectDelay: Duration = AppConstants.API.reconnectDelay,
        decisionAlertsEnabled: Bool = true,
        replyGate: DecisionReplyGate = .shared,
        decisionActivitySync: @escaping @MainActor ([HistoryMessage], Bool) async -> Void = {
            await DecisionActivityManager.sync(pending: $0, alertsEnabled: $1)
        }
    ) {
        self.reconnectDelay = reconnectDelay
        self.decisionAlertsEnabled = decisionAlertsEnabled
        self.replyGate = replyGate
        self.decisionActivitySync = decisionActivitySync
        gateObservation = replyGate.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// The choice in flight per decision, from any entry point; every button surface reads it.
    var replying: [MessageID: String] { replyGate.inFlight }

    /// Open option decisions from the shared Today ranking; only the server's required-input
    /// list can make a decision open, so history never reopens an answered card.
    var pending: [HistoryMessage] {
        todaySnapshot(now: .now).decisions.filter { !$0.options.isEmpty }.map(\.message)
    }

    var pendingCount: Int { pending.count }

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
        // An empty projection while inputs load is unknown, not an authoritative empty list.
        // Turning alerts off ends every activity regardless of inputs, so it must not wait.
        guard requiredInputLoaded || !decisionAlertsEnabled else { return }
        let candidates = todaySnapshot(now: .now).decisions.map(\.message)
        await decisionActivitySync(candidates, decisionAlertsEnabled)
    }

    func start(api: any BossServing) {
        stop()
        self.api = api
        agentAvatars.connect(api: api as? any AgentsServing)
        connectionState = .connecting
        streamTask = Task { [weak self] in await self?.consume(api) }
        startRequiredInputs(api)
        configureHistorySync(api)
        requestHistorySync()
        Task { await refreshRequiredInputs() }
    }

    func retryConnection() {
        guard let api else { return }
        streamTask?.cancel()
        connectionState = .connecting
        streamTask = Task { [weak self] in await self?.consume(api) }
        retryRequiredInputConnection()
        refreshHistory()
    }

    func rejectAuthorization(_ error: Error) {
        stop()
        connectionState = .failed(String(localized: "Session expired — reconnect in Settings."))
        requiredInputError = error.localizedDescription
        loadError = error.localizedDescription
        let epoch = requiredEpoch
        Task { [weak self] in
            guard let self, self.requiredEpoch == epoch, self.api == nil else { return }
            await self.decisionActivitySync([], false)
        }
    }

    func stop() {
        agentAvatars.disconnect()
        streamTask?.cancel()
        historyTask?.cancel()
        if let historySync { Task { await historySync.stop() } }
        historySync = nil
        historyVersion += 1
        historyRequestsInFlight = 0
        replyGate.reset()
        stopRequiredInputs()
        streamTask = nil
        historyTask = nil
        cancelExpiries()
        api = nil
        history = []
        withdrawn = []
        settledIDs = []
        localResolutions = [:]
        openedMessages = [:]
        didLoad = false
        historyCheckedAt = nil
        isRefreshing = false
        replyConfirmation = nil
        replyFeedback = [:]
        loadError = nil
        connectionState = .disconnected
    }

    /// Commit how a reply landed: a sent choice settles the card; nil rolls back the
    /// optimistic state. A closed reply keeps the card read-only until its recorded outcome arrives.
    func settleReply(_ choice: String?, for id: MessageID, error: String? = nil, closed: Bool = false,
                     answeredBy: AnsweringDevice? = nil) {
        if let choice {
            withdrawn.insert(id)
            settledIDs.insert(id)
            localResolutions[id] = DecisionSettlement(answer: choice, source: "ios", answeredBy: answeredBy)
        } else if closed {
            withdrawn.insert(id)
            settledIDs.insert(id)
            localResolutions[id] = nil
        } else {
            withdrawn.remove(id)
            settledIDs.remove(id)
            localResolutions[id] = nil
        }
        if let error { loadError = error }
    }

    private func consume(_ api: any BossServing) async {
        var failures = 0
        while !Task.isCancelled {
            if connectionState != .connected { connectionState = .connecting }
            let stream = await api.messageStream()
            connectionState = .connected
            agentAvatars.refresh()
            var endedCleanly = false
            do {
                for try await event in stream {
                    failures = 0            // a live stream delivering data
                    handle(event)
                }
                endedCleanly = true
            } catch where !Task.isCancelled {
                if (error as? HibossAPIError)?.isAuthFailure == true {
                    // A rejected token won't fix itself — stop reconnecting and
                    // surface it instead of retrying forever every few seconds.
                    rejectAuthorization(error)
                    return
                }
                connectionState = .failed(error.localizedDescription)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            // The server rotates the stream every few minutes: a clean end stays connected
            // and reconnects promptly. Only an error backs off and shows a reconnect state.
            if endedCleanly {
                failures = 0
                try? await Task<Never, Never>.sleep(for: reconnectDelay)
                continue
            }
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
            requestHistorySync(debounced: true)
        case let .resolved(resolution):
            withdrawn.insert(resolution.id)
            settledIDs.insert(resolution.id)
            if let settled = DecisionSettlement(resolution: resolution) {
                localResolutions[resolution.id] = settled
            }
            requestHistorySync(debounced: true)
        }
    }

    /// Prefer the persisted reply (body, source, automatic marker) over an optimistic guess.
    func adoptHistoryReplies() {
        for message in history where message.isDecision {
            guard let found = DecisionSettlement.fromReply(in: history, for: message.id) else { continue }
            localResolutions[message.id] = found
            settledIDs.insert(message.id)
        }
    }

    /// Arm one timer per pending deadline; when it fires, republish so `pending`
    /// recomputes and the now-expired decision drops to a read-only state.
    func rescheduleExpiries() {
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
