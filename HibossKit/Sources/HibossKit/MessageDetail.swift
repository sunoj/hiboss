// Targeted message-detail response returned by the boss API.
// Exports: MessageDetail, which decodes a top-level message plus its replies.
// Dependencies: HistoryMessage and Swift Decodable.

import Foundation

public struct MessageDetail: Decodable, Equatable, Sendable {
    public let message: HistoryMessage
    public let replies: [HistoryMessage]

    public init(message: HistoryMessage, replies: [HistoryMessage]) {
        self.message = message
        self.replies = replies
    }

    public init(from decoder: Decoder) throws {
        message = try HistoryMessage(from: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        replies = try values.decodeIfPresent([HistoryMessage].self, forKey: .replies) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case replies
    }
}
