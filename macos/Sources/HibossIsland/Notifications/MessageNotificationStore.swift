// Runs the passive feed and persists the boss's local message notification preference.
// Exports: MessageNotificationStore with reconnect, deduplication, and authorization state.
// Dependencies: HibossKit BossServing, Combine, UserDefaults, and MessageNotificationCenter.

import Combine
import Foundation
import HibossKit

@MainActor
final class MessageNotificationStore: ObservableObject {
    static let enabledKey = "hiboss.notifyAboutMessages"
    @Published private(set) var isEnabled: Bool
    @Published private(set) var authorization: MessageNotificationAuthorization = .unknown
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var errorMessage: String?

    private let center: any MessageNotificationCenter
    private let defaults: UserDefaults
    private let reconnectDelay: Duration
    private var seenIDs: Set<MessageID> = []
    private var streamTask: Task<Void, Never>?
    private var authorizationTask: Task<Void, Never>?

    init(
        center: any MessageNotificationCenter,
        defaults: UserDefaults = .standard,
        reconnectDelay: Duration = AppConstants.API.reconnectDelay
    ) {
        self.center = center
        self.defaults = defaults
        self.reconnectDelay = reconnectDelay
        isEnabled = defaults.object(forKey: Self.enabledKey) == nil
            ? true : defaults.bool(forKey: Self.enabledKey)
        center.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        center.isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        if enabled { Task { await prepareAuthorization() } }
    }

    func refreshAuthorization() async {
        authorization = await center.authorization()
    }

    func prepareAuthorization() async {
        if let authorizationTask { await authorizationTask.value; return }
        let task = Task {
            await refreshAuthorization()
            guard isEnabled, authorization == .notDetermined else { return }
            do {
                try await center.requestAuthorization()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            await refreshAuthorization()
        }
        authorizationTask = task
        await task.value
        authorizationTask = nil
    }

    func connect(api: any BossServing) {
        disconnect()
        connectionState = .connecting
        streamTask = Task { [weak self] in await self?.consumeStreams(from: api) }
    }

    func disconnect() {
        streamTask?.cancel()
        streamTask = nil
        connectionState = .disconnected
    }

    func receive(_ message: HistoryMessage) async {
        guard !Task.isCancelled, message.direction == "agent_to_boss",
              message.options.isEmpty, seenIDs.insert(message.id).inserted, isEnabled else { return }
        await prepareAuthorization()
        guard !Task.isCancelled, isEnabled,
              authorization == .authorized || authorization == .provisional else { return }
        do {
            try await center.post(MessageNotice(message: message))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func consumeStreams(from api: any BossServing) async {
        while !Task.isCancelled {
            connectionState = .connecting
            let stream = await api.feedStream()
            guard !Task.isCancelled else { return }
            connectionState = .connected
            do {
                for try await message in stream { await receive(message) }
            } catch where !Task.isCancelled {
                connectionState = .failed(error.localizedDescription)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            try? await Task<Never, Never>.sleep(for: reconnectDelay)
        }
    }
}
