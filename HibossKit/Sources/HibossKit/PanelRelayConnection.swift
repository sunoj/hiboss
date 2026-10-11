// Maintains one ticket-scoped WebSocket subscription for a native panel tile.
// Exports: PanelRelayConnection with fresh-ticket reconnect and snapshot requests.
// Dependencies: Foundation URLSessionWebSocketTask and ConnectionConfig.

import Foundation
import OSLog

@MainActor
public final class PanelRelayConnection {

    private static let log = Logger(subsystem: "ai.hiboss.native", category: "panel-relay")

    private let config: ConnectionConfig
    private let panelID: String
    private let isWall: Bool
    private let onFrame: (PanelRelayFrame) -> Void
    private let onDisconnect: () -> Void
    private let onWallConnected: () -> Void
    private var socket: URLSessionWebSocketTask?
    private var connectionTask: Task<Void, Never>?
    private var stopped = false

    public init(
        config: ConnectionConfig,
        panelID: String,
        isWall: Bool = false,
        onFrame: @escaping (PanelRelayFrame) -> Void,
        onDisconnect: @escaping () -> Void,
        onWallConnected: @escaping () -> Void = {}
    ) {
        self.config = config
        self.panelID = panelID
        self.isWall = isWall
        self.onFrame = onFrame
        self.onDisconnect = onDisconnect
        self.onWallConnected = onWallConnected
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
            var phase = "ticket"
            do {
                let api = HibossAPI(config: config)
                let ticket = try await (isWall ? api.issuePanelWallConnectionTicket()
                    : api.issuePanelConnectionTicket(panelID: panelID))
                let task = makeSocket(ticket: ticket.ticket)
                socket = task
                phase = "subscribe"
                task.resume()
                try await task.send(.string(subscribeMessage))
                phase = "receive"
                try await receive(from: task)
            } catch {
                let failure = error as NSError
                var status = (socket?.response as? HTTPURLResponse)?.statusCode ?? 0
                if case let HibossAPIError.requestFailed(code, _) = error { status = code }
                let summary = "wall=\(isWall) phase=\(phase) domain=\(failure.domain)"
                    + " code=\(failure.code) http=\(status)"
                Self.log.error("relay failed \(summary, privacy: .public)")
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
        var wallAcknowledged = false
        while !stopped && !Task.isCancelled {
            let message = try await task.receive()
            let data: Data
            switch message {
            case let .string(value): data = Data(value.utf8)
            case let .data(value): data = value
            @unknown default: continue
            }
            guard !stopped, !Task.isCancelled else { return }
            if let frame = try? JSONDecoder().decode(PanelRelayFrame.self, from: data) {
                deliver(frame, wallAcknowledged: &wallAcknowledged)
            }
        }
    }

    func deliver(_ frame: PanelRelayFrame, wallAcknowledged: inout Bool) {
        if isWall, frame == .wallChanged, !wallAcknowledged {
            wallAcknowledged = true
            Self.log.info("wall subscription acknowledged")
            onWallConnected()
            return
        }
        if case .snapshot = frame { Self.log.info("panel snapshot received") }
        onFrame(frame)
    }

    private var subscribeMessage: String {
        let kind = isWall ? "wall.subscribe" : "subscribe"
        return "{\"protocolVersion\":2,\"kind\":\"\(kind)\",\"panelId\":\"\(panelID)\"}"
    }
}
