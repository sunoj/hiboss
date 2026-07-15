// Coordinates the user-visible flow from streamed option messages to boss replies.
// Exports: OptionFlowStore, ConnectionState, and PresentationState.
// Dependencies: BossServing domain contract and Combine observation.

import Combine
import Foundation

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)

    var label: String {
        switch self {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting"
        case .connected: "Listening"
        case .failed: "Connection failed"
        }
    }
}

enum PresentationState: Equatable {
    case idle
    case ready
    case submitting(String)
    case failed(String)
}

@MainActor
final class OptionFlowStore: ObservableObject {
    @Published private(set) var activeMessage: OptionMessage?
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var presentationState: PresentationState = .idle

    private let reconnectDelay: Duration
    private var api: (any BossServing)?
    private var queuedMessages: [OptionMessage] = []
    private var seenMessageIDs: Set<MessageID> = []
    private var streamTask: Task<Void, Never>?
    private var expirationTasks: [MessageID: Task<Void, Never>] = [:]

    init(reconnectDelay: Duration = AppConstants.API.reconnectDelay) {
        self.reconnectDelay = reconnectDelay
    }

    func connect(api: any BossServing) {
        disconnect()
        self.api = api
        connectionState = .connecting
        streamTask = Task { [weak self] in
            await self?.consumeStreams(from: api)
        }
    }

    func disconnect() {
        streamTask?.cancel()
        expirationTasks.values.forEach { $0.cancel() }
        streamTask = nil
        expirationTasks.removeAll()
        api = nil
        activeMessage = nil
        queuedMessages.removeAll()
        seenMessageIDs.removeAll()
        presentationState = .idle
        connectionState = .disconnected
    }

    func choose(_ choice: String) async {
        guard let message = activeMessage, message.options.contains(choice), let api else {
            return
        }
        presentationState = .submitting(choice)
        do {
            _ = try await api.reply(to: message.id, with: choice)
            resolve(message.id)
        } catch {
            presentationState = .failed(error.localizedDescription)
        }
    }

    private func consumeStreams(from api: any BossServing) async {
        while !Task.isCancelled {
            connectionState = .connecting
            let stream = await api.messageStream()
            connectionState = .connected
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
        case let .message(message): receive(message)
        case let .resolved(resolution): resolve(resolution.id)
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

    private func resolve(_ messageID: MessageID) {
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
            self?.resolve(message.id)
        }
    }

    private func showNextMessage() {
        activeMessage = queuedMessages.isEmpty ? nil : queuedMessages.removeFirst()
        presentationState = activeMessage == nil ? .idle : .ready
    }
}
