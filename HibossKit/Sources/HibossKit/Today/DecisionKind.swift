// Which messages are decisions at all, mirroring the server's required-input query.
// Exports: HistoryMessage.isDecision; whether one is still open is the required-input list's call.
// Dependencies: HistoryMessage.

import Foundation

extension HistoryMessage {
    /// Same shape the server's open list selects: an agent→boss message with options or a
    /// blocking ask. Message type and a default option alone do not make a decision.
    public var isDecision: Bool {
        direction == "agent_to_boss" && (!options.isEmpty || mode == "blocking")
    }
}
