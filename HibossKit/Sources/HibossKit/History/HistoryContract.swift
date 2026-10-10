// Incremental history response contracts shared by native clients.
// Exports HistoryResponse and BossServing history defaults.
// Depends on Foundation and the shared domain messages.

import Foundation

public struct HistoryResponse: Codable, Equatable, Sendable {
    public let messages: [HistoryMessage]
    public let total: Int
    public let cursor: String?
    public let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case messages, total, cursor
        case hasMore = "has_more"
    }

    public init(messages: [HistoryMessage], total: Int, cursor: String? = nil, hasMore: Bool? = nil) {
        self.messages = messages
        self.total = total
        self.cursor = cursor
        self.hasMore = hasMore
    }
}

public extension BossServing {
    func fetchHistoryPage(updatedAfter: String?) async throws -> HistoryResponse {
        let messages = try await fetchHistory()
        return HistoryResponse(messages: messages, total: messages.count)
    }
}
