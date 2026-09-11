// Maintains one ticket-scoped WebSocket subscription for a native panel tile.
// Exports: PanelRelayConnection with fresh-ticket reconnect and snapshot requests.
// Dependencies: Foundation URLSessionWebSocketTask and ConnectionConfig.

import Foundation

@MainActor
public final class PanelRelayConnection {

    private let config: ConnectionConfig
    private let panelID: String
    private let isWall: Bool
    private let onFrame: (PanelRelayFrame) -> Void
    private let onDisconnect: () -> Void
    private var socket: URLSessionWebSocketTask?
    private var connectionTask: Task<Void, Never>?
    private var stopped = false

    public init(
        config: ConnectionConfig,
        panelID: String,
        isWall: Bool = false,
        onFrame: @escaping (PanelRelayFrame) -> Void,
        onDisconnect: @escaping () -> Void
    ) {
        self.config = config
        self.panelID = panelID
        self.isWall = isWall
        self.onFrame = onFrame
        self.onDisconnect = onDisconnect
    }

    public func start() {
        guard connectionTask == nil else { return }
        stopped = false
        connectionTask = Task { [weak self] in await self?.run() }
    }

    public func stop() {
        stopped = true
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        connectionTask?.cancel()
        connectionTask = nil
    }

    public func requestSnapshot() {
        guard let socket else { return }
        Task { try? await socket.send(.string(subscribeMessage)) }
    }

    private func run() async {
        var delay: UInt64 = 1_000_000_000
        while !stopped && !Task.isCancelled {
            do {
                let api = HibossAPI(config: config)
                let ticket = try await (isWall ? api.issuePanelWallConnectionTicket() : api.issuePanelConnectionTicket(panelID: panelID))
                let task = makeSocket(ticket: ticket.ticket)
                socket = task
                task.resume()
                try await task.send(.string(subscribeMessage))
                try await receive(from: task)
            } catch {
                // A failed handshake or receive is a subscription loss; the next loop gets a new ticket.
            }
            socket?.cancel(with: .goingAway, reason: nil)
            socket = nil
            guard !stopped && !Task.isCancelled else { return }
            onDisconnect()
            try? await Task.sleep(nanoseconds: delay)
            delay = min(delay * 2, 30_000_000_000)
        }
    }

    private func makeSocket(ticket: String) -> URLSessionWebSocketTask {
        var components = URLComponents(url: config.serverURL.appendingPathComponent("api/panel-relay"), resolvingAgainstBaseURL: false)
        components?.scheme = config.serverURL.scheme == "https" ? "wss" : "ws"
        var request = URLRequest(url: components?.url ?? config.serverURL)
        request.setValue(ticket, forHTTPHeaderField: "X-Panel-Connection-Ticket")
        return URLSession.shared.webSocketTask(with: request)
    }

    private func receive(from task: URLSessionWebSocketTask) async throws {
        while !stopped && !Task.isCancelled {
            let message = try await task.receive()
            let data: Data
            switch message {
            case let .string(value): data = Data(value.utf8)
            case let .data(value): data = value
            @unknown default: continue
            }
            if let frame = try? JSONDecoder().decode(PanelRelayFrame.self, from: data) { onFrame(frame) }
        }
    }

    private var subscribeMessage: String {
        let kind = isWall ? "wall.subscribe" : "subscribe"
        return "{\"protocolVersion\":2,\"kind\":\"\(kind)\",\"panelId\":\"\(panelID)\"}"
    }
}
