// Incremental history response and cache lookup contracts shared by native clients.
// Exports HistoryResponse, HistoryCacheKey, and BossServing history defaults.
// Depends on Foundation and CryptoKit; cache keys never contain credentials.

import CryptoKit
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

public struct HistoryCacheKey: Sendable {
    let server: String
    let credential: String
    var account: String { server + ":" + credential }

    public init(config: ConnectionConfig) {
        server = Self.digest(config.serverURL.absoluteString)
        credential = Self.digest(config.bossToken)
    }

    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public extension BossServing {
    var historyCacheKey: HistoryCacheKey? { nil }
    func fetchHistoryBossID() async throws -> String? { nil }
    func fetchHistoryPage(updatedAfter: String?) async throws -> HistoryResponse {
        let messages = try await fetchHistory()
        return HistoryResponse(messages: messages, total: messages.count)
    }
}
