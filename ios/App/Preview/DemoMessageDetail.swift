// Targeted message lookup for demo-mode notification deep links.
// Exports: DemoBossAPI.fetchMessage without coupling it to history timing.
// Dependencies: DemoBossAPI fixtures and HibossKit message contracts.

import HibossKit

extension DemoBossAPI {
    func fetchMessage(_ messageID: MessageID) async throws -> MessageDetail {
        guard let message = messages.first(where: { $0.id == messageID }) else {
            throw HibossAPIError.requestFailed(status: 404, message: "")
        }
        let replies = messages.filter { $0.replyTo == messageID.rawValue }
        return MessageDetail(message: message, replies: replies)
    }
}
