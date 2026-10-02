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
    @Published public private(set) var historyMessages: [HistoryMessage] = []
    @Published public private(set) var historyState: HistoryState = .idle
    /// Per-message outcome of the last reply that did not land; cleared when one is accepted.
    @Published public private(set) var replyFeedback: [MessageID: ReplyFeedback] = [:]

    private let reconnectDelay: Duration
    private var api: (any BossServing)?
    private var queuedMessages: [OptionMessage] = []
    private var seenMessageIDs: Set<MessageID> = []
    private var streamTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    private var expirationTasks: [MessageID: Task<Void, Never>] = [:]
    private var resolvedDismissTask: Task<Void, Never>?
    /// How long the "answered on <device>" card lingers before advancing.
    private let resolvedLinger: Duration = .seconds(3)

    public init(reconnectDelay: Duration = AppConstants.API.reconnectDelay) {
        self.reconnectDelay = reconnectDelay
    }

    public func connect(api: any BossServing) {
        disconnect()
        self.api = api
        connectionState = .connecting
        streamTask = Task { [weak self] in
            await self?.consumeStreams(from: api)
        }
        refreshHistoryInBackground()
    }

    public func disconnect() {
        streamTask?.cancel()
        historyTask?.cancel()
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
        replyFeedback.removeAll()
        connectionState = .disconnected
    }

    @Published public private(set) var projectSessions: [ProjectSession] = []

    public func refreshHistory() async {
        guard let api else { return }
        historyState = .loading
        do {
            historyMessages = try await api.fetchHistory()
            historyState = .loaded
            reconcileActiveAgainstHistory()
            if let sessionsAPI = api as? any SessionsServing {
                projectSessions = (try? await sessionsAPI.projectSessions()) ?? []
            }
        } catch where Task.isCancelled {
            return
        } catch {
            historyState = .failed(error.localizedDescription)
        }
    }

    /// Dismiss any shown/queued option the freshly-loaded history now marks
    /// resolved. Unlike the derived iOS inbox, this store holds `activeMessage`
    /// imperatively, so without this a card answered elsewhere while our stream
    /// was reconnecting would linger until its local expiry.
    private func reconcileActiveAgainstHistory() {
        func resolvedInHistory(_ id: MessageID) -> HistoryMessage? {
            historyMessages.first { $0.id == id && ($0.status == "replied" || $0.status == "expired") }
        }
        queuedMessages.removeAll { resolvedInHistory($0.id) != nil }
        guard let active = activeMessage, let resolved = resolvedInHistory(active.id) else { return }
        // Already showing the resolved card for this id — don't restart its linger
        // on a subsequent history refresh.
        if case .resolved = presentationState { return }
        let reply = historyMessages.first { $0.replyTo == active.id.rawValue }
        resolve(OptionResolution(
            id: active.id,
            status: resolved.status == "expired" ? .expired : .replied,
            answer: reply?.body,
            source: reply?.metadata?.source
        ))
    }

    /// `messageID` is the message the caller was looking at: a skip or a stream resolution can
    /// advance `activeMessage` between the click and this call, and the answer must not follow.
    @discardableResult
    public func choose(_ choice: String, for messageID: MessageID) async -> Bool {
        guard let message = activeMessage, message.id == messageID,
              message.options.contains(choice) else { return false }
        return await send(choice, for: message)
    }

    /// Answers a past (history) option message by id, independent of the live `activeMessage`.
    /// True only when the server accepted this reply; otherwise `replyFeedback[messageID]` says why.
    @discardableResult
    public func answerHistory(_ choice: String, for messageID: MessageID) async -> Bool {
        guard let api else {
            replyFeedback[messageID] = .failed(kitL("Disconnected"))
            return false
        }
        replyFeedback[messageID] = nil
        do {
            switch try await api.reply(to: messageID, with: choice) {
            case .accepted:
                await refreshHistory()
                return true
            case .alreadyResolved:
                await settleConflict(for: messageID)
                return false
            }
        } catch {
            replyFeedback[messageID] = .failed(error.localizedDescription)
            return false
        }
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

    /// Replies to the live message. Only `.accepted` dismisses it as this device's answer.
    private func send(_ body: String, for message: OptionMessage) async -> Bool {
        guard let api else { return false }
        replyFeedback[message.id] = nil
        presentationState = .submitting(body)
        do {
            switch try await api.reply(to: message.id, with: body) {
            case .accepted:
                dismiss(message.id)
                refreshHistoryInBackground()
                return true
            case .alreadyResolved:
                await settleConflict(for: message.id)
                return false
            }
        } catch {
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
    private func settleConflict(for messageID: MessageID) async {
        replyFeedback[messageID] = .alreadyResolved
        await refreshHistory()
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
            // Reconcile on every (re)connect: a resolution that happened while we
            // were between 5-minute stream cycles is otherwise never delivered.
            refreshHistoryInBackground()
            do {
                for try await event in stream {
                    receive(event)
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

    private func refreshHistoryInBackground() {
        historyTask?.cancel()
        historyTask = Task { [weak self] in
            await self?.refreshHistory()
        }
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

    private func resolve(_ resolution: OptionResolution) {
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

    /// Local dismissal without a resolved card (this device answered, or skip).
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
