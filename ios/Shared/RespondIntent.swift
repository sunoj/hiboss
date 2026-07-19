// App Intent behind the Live Activity's Approve/Reject buttons.
// Exports: RespondDecisionIntent — replies via the boss API, then ends the activity.
// Dependencies: AppIntents, ActivityKit, HibossKit. iOS 17+.

import ActivityKit
import AppIntents
import Foundation
import HibossKit

struct RespondDecisionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Respond to decision"

    @Parameter(title: "Message ID") var messageID: String
    @Parameter(title: "Choice") var choice: String

    init() {}

    init(messageID: String, choice: String) {
        self.messageID = messageID
        self.choice = choice
    }

    func perform() async throws -> some IntentResult {
        if let api = HiBossStore.bossAPI() {
            _ = try? await api.reply(to: MessageID(rawValue: messageID), with: choice)
        }
        await endActivity()
        return .result()
    }

    private func endActivity() async {
        for activity in Activity<DecisionActivityAttributes>.activities
        where activity.attributes.messageID == messageID {
            var state = activity.content.state
            state.resolved = true
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .after(.now + 2)
            )
        }
    }
}
