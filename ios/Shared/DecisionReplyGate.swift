// The one admission point for every decision reply: Home, transcript, detail, notification
// actions and Live Activity intents. At most one submission per decision id is in flight.
// Exports: DecisionReplyGate, DecisionSubmission. Dependencies: Combine, HibossKit BossServing.

import Combine
import Foundation
import HibossKit

/// The answerable rule shared by every iOS decision surface and submission entry point.
enum DecisionAnswerability: Equatable {
    case checking, open, closed

    init(id: MessageID, openIDs: Set<MessageID>, loaded: Bool, withdrawn: Set<MessageID> = []) {
        if withdrawn.contains(id) { self = .closed }
        else if !loaded { self = .checking }
        else { self = openIDs.contains(id) ? .open : .closed }
    }

    var label: String? {
        switch self {
        case .checking: String(localized: "Checking…")
        case .closed: String(localized: "No longer open")
        case .open: nil
        }
    }
}

/// What became of one reply attempt.
enum DecisionSubmission: Equatable {
    case accepted
    case alreadyResolved
    case failed(String)
    /// Another reply for this decision was still in flight, so nothing was sent.
    case busy
}

@MainActor
final class DecisionReplyGate: ObservableObject {
    /// Shared by the app's surfaces and the intents that run in the app process.
    static let shared = DecisionReplyGate()

    /// The choice in flight per decision. Every reply button reads it to disable itself.
    @Published private(set) var inFlight: [MessageID: String] = [:]
    private var generation = 0

    /// Called only at the inbox's account boundary; obsolete submissions retain no current slot.
    func reset() {
        generation += 1
        inFlight = [:]
    }

    /// Sends the choice unless a reply for this decision is already in flight. The slot is
    /// released on every exit (success, already-resolved, failure, cancellation) and any
    /// Live Activity for the decision shows the submission, then its recorded outcome.
    func submit(_ choice: String, to id: MessageID, via api: any BossServing,
                answerability: DecisionAnswerability? = nil) async -> DecisionSubmission {
        guard inFlight[id] == nil else { return .busy }
        let version = generation
        let text = choice.trimmingCharacters(in: .whitespacesAndNewlines)
        inFlight[id] = text
        defer {
            if version == generation { inFlight[id] = nil }
        }
        await DecisionActivityLink.showSubmitting(text, for: id)
        let progress = submissionProgress(text, for: id, version: version)
        defer { progress.cancel() }
        let submission: DecisionSubmission
        do {
            let state: DecisionAnswerability
            if let answerability { state = answerability }
            else { state = try await loadAnswerability(for: id, via: api) }
            guard version == generation else { return .failed(String(localized: "Connection isn't ready.")) }
            if state != .open {
                submission = state == .closed ? .alreadyResolved : .failed(state.label ?? "")
            } else {
                switch try await api.reply(to: id, with: choice) {
                case .accepted: submission = .accepted
                case .alreadyResolved: submission = .alreadyResolved
                }
            }
        } catch {
            submission = .failed(error.localizedDescription)
        }
        progress.cancel()
        guard version == generation else { return submission }
        await DecisionActivityLink.settle(id, after: submission, choice: text, api: api)
        return submission
    }

    private func submissionProgress(_ text: String, for id: MessageID, version: Int) -> Task<Void, Never> {
        Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
                guard version == generation else { return }
                await DecisionActivityLink.showSubmitting(text, for: id, progressVisible: true)
                try await Task.sleep(for: .milliseconds(7_700))
                guard version == generation else { return }
                await DecisionActivityLink.showSubmitting(text, for: id, progressVisible: true, slow: true)
            } catch { return }
        }
    }

    private func loadAnswerability(for id: MessageID, via api: any BossServing) async throws
        -> DecisionAnswerability {
        guard let service = api as? any RequiredInputServing else { return .checking }
        let inputs = try await service.fetchRequiredInputs()
        let today = TodaySnapshot(history: [], requiredInputs: inputs, health: .loading,
                                  coverageComplete: true, now: .now)
        let state = DecisionAnswerability(id: id, openIDs: Set(today.decisions.map(\.id)), loaded: true)
        if state == .closed {
            let message = try await api.fetchMessage(id).message
            if !message.isDecision { return .open }
        }
        return state
    }
}
