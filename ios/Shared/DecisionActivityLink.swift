// Mirrors DecisionReplyGate onto a decision's Live Activity: disabled while a reply is in
// flight, then ended with the recorded outcome, whichever surface sent the reply.
// Exports: DecisionActivityLink. Dependencies: ActivityKit, HibossKit, DecisionActivity.

import ActivityKit
import Foundation
import HibossKit

@MainActor
enum DecisionActivityLink {
    nonisolated private static func activities(for id: MessageID) -> [Activity<DecisionActivityAttributes>] {
        Activity<DecisionActivityAttributes>.activities.filter { $0.attributes.messageID == id.rawValue }
    }

    static func showSubmitting(_ choice: String, for id: MessageID) async {
        for activity in activities(for: id) {
            var state = activity.content.state
            state.submitting = choice
            await activity.update(ActivityContent(state: state, staleDate: activity.content.staleDate))
        }
    }

    /// A failed send re-enables the buttons; a settled decision ends with what was recorded.
    /// An already-resolved decision reads the winning reply rather than claiming this one.
    static func settle(
        _ id: MessageID, after submission: DecisionSubmission, choice: String, api: any BossServing
    ) async {
        let running = activities(for: id)
        guard !running.isEmpty else { return }
        let completion = await completion(of: id, after: submission, choice: choice, api: api)
        for activity in running {
            var state = activity.content.state
            state.submitting = nil
            state.completion = completion
            if completion == nil {
                await activity.update(ActivityContent(state: state, staleDate: activity.content.staleDate))
            } else {
                await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(.now + 2))
            }
        }
    }

    /// The outcome an activity ends with; nil keeps it open. This device's accepted reply is
    /// `answered` even when it equals the default; only the recorded marker makes it automatic.
    static func completion(
        of id: MessageID, after submission: DecisionSubmission, choice: String, api: any BossServing
    ) async -> DecisionCompletion? {
        switch submission {
        case .accepted: return .answered(choice)
        case .alreadyResolved: return .recorded(in: try? await api.fetchMessage(id))
        case .failed, .busy: return nil
        }
    }
}
