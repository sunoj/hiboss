// State for one approval sheet: resolves a request ID, then approves or rejects it.
// Exports: JoinRequestReviewPhase and JoinRequestReview, shared by the macOS and iOS sheets.
// Dependencies: Combine ObservableObject and JoinRequestsModel.

import Combine
import Foundation

public enum JoinRequestReviewPhase: Equatable, Sendable {
    case loading
    case ready(JoinRequest)
    case approved(JoinRequest, JoinApproval)
    case rejected(JoinRequest)
    case unavailable(String)
}

@MainActor
public final class JoinRequestReview: ObservableObject {
    @Published public private(set) var phase: JoinRequestReviewPhase = .loading
    @Published public private(set) var failureMessage: String?
    @Published public private(set) var isDeciding = false
    public let requestID: String
    private let model: JoinRequestsModel
    private var authorizationObservation: AnyCancellable?
    private var generation = 0

    public init(requestID: String, model: JoinRequestsModel) {
        self.requestID = requestID
        self.model = model
        authorizationObservation = AccountAuthorization.shared.observe { [weak self] error in
            self?.generation += 1
            self?.phase = .unavailable(error.localizedDescription)
            self?.failureMessage = nil
            self?.isDeciding = false
        }
        if let known = model.request(id: requestID) { phase = .ready(known) }
    }

    public func load() async {
        if case .ready = phase { return }
        let version = generation
        let result = await model.lookup(id: requestID)
        guard version == generation else { return }
        switch result {
        case let .found(request): phase = .ready(request)
        case .notPending: phase = .unavailable(JoinRequestError.notFound.localizedDescription)
        case .forbidden: phase = .unavailable(JoinRequestError.forbidden.localizedDescription)
        case let .failed(message): phase = .unavailable(message)
        }
    }

    /// Wire only to an explicit Approve button on the screen that shows the verification code.
    public func approve() async {
        guard case let .ready(request) = phase, request.canApprove else { return }
        await decide(request, model.approve)
    }

    public func reject() async {
        guard case let .ready(request) = phase else { return }
        await decide(request, model.reject)
    }

    private func decide(
        _ request: JoinRequest, _ action: (JoinRequest) async -> JoinDecisionResult
    ) async {
        guard !isDeciding else { return }
        isDeciding = true
        failureMessage = nil
        defer { isDeciding = false }
        let version = generation
        let result = await action(request)
        guard version == generation else { return }
        switch result {
        case let .approved(approval): phase = .approved(request, approval)
        case .rejected: phase = .rejected(request)
        case let .failed(message): settle(after: message)
        }
    }

    /// After a failure the sheet stays on the request only while the server still lists it.
    private func settle(after message: String) {
        if model.isForbidden {
            phase = .unavailable(message)
        } else if let current = model.request(id: requestID) {
            phase = .ready(current)
            failureMessage = message
        } else if model.state == .loaded {
            phase = .unavailable(message)
        } else {
            failureMessage = message
        }
    }
}
