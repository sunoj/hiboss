// Targeted message-detail request used by notification deep links.
// Exports: HibossAPI.fetchMessage, avoiding a full-history fetch on cold launch.
// Dependencies: HibossAPI request helpers and MessageDetail decoding.

import Foundation

extension HibossAPI {
    public func fetchMessage(_ messageID: MessageID) async throws -> MessageDetail {
        let endpoint = apiURL
            .appendingPathComponent("messages")
            .appendingPathComponent(messageID.rawValue)
        var request = authorizedRequest(url: endpoint, method: "GET")
        request.timeoutInterval = AppConstants.API.notificationMessageTimeout
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decoder.decode(MessageDetail.self, from: data)
    }
}
