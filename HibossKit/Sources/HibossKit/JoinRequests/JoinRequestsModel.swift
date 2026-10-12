// Shared view model for pending machine join requests on macOS and iOS.
// Exports: JoinRequestsState, JoinRequestLookup, JoinDecisionResult, and JoinRequestsModel.
// Dependencies: Combine ObservableObject and a JoinRequestServing client.

import Combine
import Foundation

public enum JoinRequestsState: Equatable, Sendable {
    case idle, loading, loaded, forbidden
    case failed(String)
}

public enum JoinRequestLookup: Equatable, Sendable {
    case found(JoinRequest)
    case notPending
    case forbidden
    case failed(String)
}

public enum JoinDecisionResult: Equatable, Sendable {
    case approved(JoinApproval)
    case rejected
    case failed(String)
}

@MainActor
public final class JoinRequestsModel: ObservableObject {
    @Published public private(set) var requests: [JoinRequest] = []
    @Published public private(set) var state: JoinRequestsState = .idle
    @Published public private(set) var didLoad = false
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var decidingID: String?
    /// Called once per request ID the model has never seen, across refreshes and reconnects.
    public var onNewRequests: (([JoinRequest]) -> Void)?

    private let serviceProvider: @MainActor () -> (any JoinRequestServing)?
    private let pollInterval: Duration
    private var seenIDs: Set<String> = []
    private(set) var generation = 0

    public init(
        pollInterval: Duration = .seconds(30),
        serviceProvider: @escaping @MainActor () -> (any JoinRequestServing)?
    ) {
        self.pollInterval = pollInterval
        self.serviceProvider = serviceProvider
    }

    public var pendingCount: Int { requests.count }
    public var isForbidden: Bool { state == .forbidden }

    public func request(id: String) -> JoinRequest? {
        requests.first { $0.id == id }
    }

    public func refresh() async {
        guard !isRefreshing, !Task.isCancelled else { return }
        let version = generation
        guard let service = serviceProvider() else {
            requests = []
            state = .idle
            return
        }
        if !didLoad { state = .loading }
        isRefreshing = true
        defer { if version == generation { isRefreshing = false } }
        do {
            let pending = try await service.listPendingJoinRequests()
                .filter { $0.status == "pending" }
            guard version == generation, !Task.isCancelled else { return }
            requests = pending
            state = .loaded
            didLoad = true
            announce(pending)
        } catch JoinRequestError.forbidden {
            guard version == generation, !Task.isCancelled else { return }
            requests = []
            state = .forbidden
        } catch {
            guard version == generation, !Task.isCancelled else { return }
            state = .failed(error.localizedDescription)
        }
    }

    /// Refreshes every `pollInterval` until cancelled; a 403 ends polling for this connection.
    public func poll() async {
        let version = generation
        while version == generation, !Task.isCancelled {
            await refresh()
            guard version == generation, state != .forbidden else { return }
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                return
            }
        }
    }

    /// Forgets the list on disconnect; seen IDs survive so a reconnect does not re-announce.
    public func reset() {
        generation &+= 1
        isRefreshing = false
        requests = []
        state = .idle
        didLoad = false
        decidingID = nil
    }

    /// Resolves a pushed or notified request ID, refreshing when it is not in the list yet.
    public func lookup(id: String) async -> JoinRequestLookup {
        let version = generation
        if let match = request(id: id) { return .found(match) }
        await refresh()
        guard version == generation, !Task.isCancelled else {
            return .failed(CancellationError().localizedDescription)
        }
        switch state {
        case .forbidden: return .forbidden
        case let .failed(message): return .failed(message)
        case .idle: return .failed(kitL("Connect to a server first."))
        default: return request(id: id).map(JoinRequestLookup.found) ?? .notPending
        }
    }

    /// Callers invoke this only from an explicit button on a screen showing `displayCode`.
    public func approve(_ request: JoinRequest) async -> JoinDecisionResult {
        guard request.canApprove else {
            return .failed(kitL("This request has no verification code, so it can’t be approved."))
        }
        return await decide(request) { service in
            .approved(try await service.approveJoinRequest(id: request.id))
        }
    }

    public func reject(_ request: JoinRequest) async -> JoinDecisionResult {
        await decide(request) { service in
            try await service.rejectJoinRequest(id: request.id)
            return .rejected
        }
    }

    private func decide(
        _ request: JoinRequest,
        _ action: (any JoinRequestServing) async throws -> JoinDecisionResult
    ) async -> JoinDecisionResult {
        let version = generation
        guard !Task.isCancelled else { return .failed(CancellationError().localizedDescription) }
        guard decidingID == nil else { return .failed(kitL("Another decision is in progress.")) }
        guard let service = serviceProvider() else {
            return .failed(kitL("Connect to a server first."))
        }
        decidingID = request.id
        defer { if version == generation { decidingID = nil } }
        do {
            let result = try await action(service)
            guard version == generation, !Task.isCancelled else {
                return .failed(CancellationError().localizedDescription)
            }
            requests.removeAll { $0.id == request.id }
            return result
        } catch let error as JoinRequestError {
            guard version == generation, !Task.isCancelled else {
                return .failed(CancellationError().localizedDescription)
            }
            if error == .forbidden {
                requests = []
                state = .forbidden
            } else {
                // 409 may mean "name taken" with the request still pending; the server decides.
                await refresh()
            }
            return .failed(error.localizedDescription)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func announce(_ pending: [JoinRequest]) {
        let fresh = pending.filter { seenIDs.insert($0.id).inserted }
        guard !fresh.isEmpty else { return }
        onNewRequests?(fresh)
    }
}
