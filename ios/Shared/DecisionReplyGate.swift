// The one admission point for every decision reply: Home, transcript, detail, notification
// actions and Live Activity intents. At most one submission per decision id is in flight.
// Exports: DecisionReplyGate, DecisionSubmission. Dependencies: Combine, HibossKit BossServing.

import Combine
import Foundation
import HibossKit

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

    /// Sends the choice unless a reply for this decision is already in flight. The slot is
    /// released on every exit (success, already-resolved, failure, cancellation) and any
    /// Live Activity for the decision shows the submission, then its recorded outcome.
    func submit(_ choice: String, to id: MessageID, via api: any BossServing) async -> DecisionSubmission {
        guard inFlight[id] == nil else { return .busy }
        let text = choice.trimmingCharacters(in: .whitespacesAndNewlines)
        inFlight[id] = text
        defer { inFlight[id] = nil }
        await DecisionActivityLink.showSubmitting(text, for: id)
        let submission: DecisionSubmission
        do {
            switch try await api.reply(to: id, with: choice) {
            case .accepted: submission = .accepted
            case .alreadyResolved: submission = .alreadyResolved
            }
        } catch {
            submission = .failed(error.localizedDescription)
        }
        await DecisionActivityLink.settle(id, after: submission, choice: text, api: api)
        return submission
    }
}
