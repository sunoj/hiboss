// Coordinates message history and the streamed option-to-reply flow.
// Exports: OptionFlowStore; its published states live in OptionFlowStates.swift.
// Dependencies: BossServing domain contract and Combine observation.

import Combine
import Foundation

@MainActor
public final class OptionFlowStore: ObservableObject {
    @Published public private(set) var activeMessage: OptionMessage?
    @Published public private(set) var connectionState: ConnectionState = .disconnected
    @Published public private(set) var presentationState: PresentationState = .idle
    @Published public internal(set) var historyMessages: [HistoryMessage] = []
    @Published public internal(set) var historyState: HistoryState = .idle
    @Published public internal(set) var historyLoadedAt: Date?
    @Published public internal(set) var isRefreshingHistory = false
    public let agentAvatars = AgentAvatarStore()
    /// Per-message outcome of the last reply that did not land; cleared when one is accepted.
    @Published public private(set) var replyFeedback: [MessageID: ReplyFeedback] = [:]

    private var authorizationObservation: AnyCancellable?
    private let reconnectDelay: Duration
    var api: (any BossServing)?
    var queuedMessages: [OptionMessage] = []
    private var seenMessageIDs: Set<MessageID> = []
    private var streamTask: Task<Void, Never>?
    var historyTask: Task<Void, Never>?
    var historySync: HistorySync?
    var historyVersion = 0
    private var expirationTasks: [MessageID: Task<Void, Never>] = [:]
    private var resolvedDismissTask: Task<Void, Never>?
    /// How long the "answered on <device>" card lingers before advancing.
    private let resolvedLinger: Duration = .seconds(3)

    public init(reconnectDelay: Duration = AppConstants.API.reconnectDelay) {
        self.reconnectDelay = reconnectDelay
        authorizationObservation = AccountAuthorization.shared.observe { [weak self] error in
            self?.disconnect()
            self?.connectionState = .failed(error.localizedDescription)
            self?.historyState = .failed(error.localizedDescription)
        }
    }

    public func connect(api: any BossServing) {
        disconnect()
        self.api = api
        agentAvatars.connect(api: api as? any AgentsServing)
        connectionState = .connecting
        streamTask = Task { [weak self] in
            await self?.consumeStreams(from: api)
        }
        configureHistorySync(api)
        refreshHistoryInBackground(debounced: false)
    }

    public func disconnect() {
        agentAvatars.disconnect()
        streamTask?.cancel()
        historyTask?.cancel()
        if let historySync { Task { await historySync.stop() } }
        historySync = nil
        historyVersion += 1
        expirationTasks.values.forEach { $0.cancel() }
        resolvedDismissTask?.cancel()
        streamTask = nil
        historyTask = nil
        resolvedDismissTask = nil
        expirationTasks.removeAll()
        api = nil
        activeMessage = nil
        queuedMessages.removeAll()
        seenMessageIDs.removeAll()
        presentationState = .idle
        historyMessages.removeAll()
        projectSessions.removeAll()
        historyState = .idle
        historyLoadedAt = nil
        isRefreshingHistory = false
        replyFeedback.removeAll()
        connectionState = .disconnected
    }

    @Published public internal(set) var projectSessions: [ProjectSession] = []

    /// `messageID` is the message the caller was looking at: a skip or a stream resolution can
    /// advance `activeMessage` between the click and this call, and the answer must not follow.
    @discardableResult
    public func choose(_ choice: String, for messageID: MessageID) async -> Bool {
        guard let message = activeMessage, message.id == messageID,
              message.options.contains(choice) else { return false }
        return await send(choice, for: message)
    }

    /// Answers with free-form text instead of one of the offered options.
    /// Returns false when the reply was empty or the server rejected it, so callers keep the draft.
    @discardableResult
    public func submit(_ reply: String, for messageID: MessageID) async -> Bool {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let message = activeMessage, message.id == messageID, !trimmed.isEmpty else {
            return false
        }
        return await send(trimmed, for: message)
    }

    /// Dismisses the message locally only — the agent keeps waiting and other channels can still answer.
    public func skip() {
        guard let message = activeMessage else { return }
        dismiss(message.id)
    }

    /// Replies to the live message. Only `.accepted` resolves it as this device's answer.
    private func send(_ body: String, for message: OptionMessage) async -> Bool {
        guard let api else { return false }
        replyFeedback[message.id] = nil
        presentationState = .submitting(body)
        let version = historyVersion
        do {
            let outcome = try await api.reply(to: message.id, with: body)
            guard version == historyVersion else { return false }
            switch outcome {
            case .accepted, .acceptedOn:
                #if os(macOS)
                let source = "macos"
                #else
                let source = "ios"
                #endif
                resolve(OptionResolution(id: message.id, status: .replied, answer: body, source: source,
                                         answeredBy: outcome.answeredBy))
                refreshHistoryInBackground()
                return true
            case .alreadyResolved:
                await settleConflict(for: message.id)
                return false
            }
        } catch {
            guard version == historyVersion else { return false }
            if AccountAuthorization.shared.reject(error) { return false }
            replyFeedback[message.id] = .failed(error.localizedDescription)
            if activeMessage?.id == message.id, case .submitting = presentationState {
                presentationState = .ready
            }
            return false
        }
    }

    /// A 409 means the decision is closed (answered elsewhere or expired). Reload history so only a
    /// recorded answer is shown as the outcome; otherwise withdraw the stale choice without inventing one.
    /// Leaves other messages and an already observed resolution for this one untouched.
    func settleConflict(for messageID: MessageID) async {
        let version = historyVersion
        replyFeedback[messageID] = .alreadyResolved
        await refreshHistory()
        guard version == historyVersion, !Task.isCancelled else { return }
        expirationTasks.removeValue(forKey: messageID)?.cancel()
        queuedMessages.removeAll { $0.id == messageID }
        guard activeMessage?.id == messageID else { return }
        if case .resolved = presentationState { return }
        showNextMessage()
    }

    private func consumeStreams(from api: any BossServing) async {
        while !Task.isCancelled {
            connectionState = .connecting
            let stream = await api.messageStream()
            connectionState = .connected
            agentAvatars.refresh()
            // Reconcile on every (re)connect: a resolution that happened while we
            // were between 5-minute stream cycles is otherwise never delivered.
            refreshHistoryInBackground()
            reconcileShownAsks()
            do {
                for try await event in stream {
                    receive(event)
                }
            } catch where !Task.isCancelled {
                if AccountAuthorization.shared.reject(error) { return }
                connectionState = .failed(error.localizedDescription)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            try? await Task<Never, Never>.sleep(for: reconnectDelay)
        }
    }

    private func receive(_ event: BossEvent) {
        switch event {
        case let .message(message):
            receive(message)
            refreshHistoryInBackground()
        case let .resolved(resolution):
            resolve(resolution)
            refreshHistoryInBackground()
        }
    }

    func setHistoryReplyFeedback(_ feedback: ReplyFeedback?, for messageID: MessageID) {
        replyFeedback[messageID] = feedback
    }

    private func receive(_ message: OptionMessage) {
        guard !message.options.isEmpty, seenMessageIDs.insert(message.id).inserted else {
            return
        }
        if let expirationDate = message.expirationDate, expirationDate <= Date() {
            return
        }
        scheduleExpiration(for: message)
        if activeMessage == nil {
            activeMessage = message
            presentationState = .ready
        } else {
            queuedMessages.append(message)
        }
    }

    func resolve(_ resolution: OptionResolution) {
        let messageID = resolution.id
        expirationTasks.removeValue(forKey: messageID)?.cancel()
        queuedMessages.removeAll { $0.id == messageID }
        guard activeMessage?.id == messageID else { return }
        // Surface the choice + where it came from before advancing to the next.
        if resolution.status == .replied, resolution.answer != nil {
            presentationState = .resolved(answer: resolution.answer, source: resolution.sourceLabel)
            resolvedDismissTask?.cancel()
            let linger = resolvedLinger
            resolvedDismissTask = Task { [weak self] in
                try? await Task<Never, Never>.sleep(for: linger)
                guard !Task.isCancelled else { return }
                self?.showNextMessage()
            }
        } else {
            showNextMessage()
        }
    }

    /// Local dismissal without a resolved card when the user skips.
    private func dismiss(_ messageID: MessageID) {
        expirationTasks.removeValue(forKey: messageID)?.cancel()
        queuedMessages.removeAll { $0.id == messageID }
        guard activeMessage?.id == messageID else { return }
        showNextMessage()
    }

    private func scheduleExpiration(for message: OptionMessage) {
        guard let expirationDate = message.expirationDate else { return }
        let delay = max(0, expirationDate.timeIntervalSinceNow)
        expirationTasks[message.id] = Task { [weak self] in
            try? await Task<Never, Never>.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.resolve(OptionResolution(id: message.id, status: .expired))
        }
    }

    private func showNextMessage() {
        activeMessage = queuedMessages.isEmpty ? nil : queuedMessages.removeFirst()
        presentationState = activeMessage == nil ? .idle : .ready
    }
}
