// App Intent behind the Live Activity's Approve/Reject buttons.
// Exports: RespondDecisionIntent — replies through DecisionReplyGate, which settles the activity.
// Dependencies: AppIntents, HibossKit, DecisionReplyGate. iOS 17+.

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

    /// Replies through the shared gate, which marks the activity as sending and then ends
    /// it with the recorded outcome. A tap while another reply is in flight sends nothing.
    @MainActor
    func perform() async throws -> some IntentResult {
        if let api = HiBossStore.replyAPI() {
            _ = await DecisionReplyGate.shared.submit(choice, to: MessageID(rawValue: messageID), via: api)
        }
        return .result()
    }
}
