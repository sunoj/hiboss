// Coordinates message history and the streamed option-to-reply flow.
// Exports: OptionFlowStore plus connection, history, and presentation states.
// Dependencies: BossServing domain contract and Combine observation.

import Combine
import Foundation

public enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)

    public var label: String {
        switch self {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting"
        case .connected: "Listening"
        case .failed: "Connection failed"
        }
    }

    /// The failure reason for `.failed`, if any — surfaced where space allows.
    public var detail: String? {
        if case let .failed(message) = self, !message.isEmpty { return message }
        return nil
    }
}

public enum PresentationState: Equatable {
    case idle
    case ready
    case submitting(String)
    case failed(String)
    /// The decision was answered elsewhere; briefly show the choice + source.
    case resolved(answer: String?, source: String?)
}

public enum HistoryState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

@MainActor
public final class OptionFlowStore: ObservableObject {
    @Published public private(set) var activeMessage: OptionMessage?
    @Published public private(set) var connectionState: ConnectionState = .disconnected
    @Published public private(set) var presentationState: PresentationState = .idle
    @Published public private(set) var historyMessages: [HistoryMessage] = []
    @Published public private(set) var historyState: HistoryState = .idle

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
        historyState = .idle
        connectionState = .disconnected
    }

    public func refreshHistory() async {
        guard let api else { return }
        historyState = .loading
        do {
            historyMessages = try await api.fetchHistory()
            historyState = .loaded
            reconcileActiveAgainstHistory()
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
    /// Used by the History window so the boss can act on decisions that are not the current popup.
    @discardableResult
    public func answerHistory(_ choice: String, for messageID: MessageID) async -> Bool {
        guard let api else { return false }
        do {
            _ = try await api.reply(to: messageID, with: choice)
            await refreshHistory()
            return true
        } catch {
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

    @discardableResult
    private func send(_ body: String, for message: OptionMessage) async -> Bool {
        guard let api else { return false }
        presentationState = .submitting(body)
        do {
            _ = try await api.reply(to: message.id, with: body)
            dismiss(message.id)
            refreshHistoryInBackground()
            return true
        } catch {
            presentationState = .failed(error.localizedDescription)
            return false
        }
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
        case let .resolved(resolution): resolve(resolution)
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
