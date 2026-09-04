// Targeted notification-message loading and detail cache for InboxStore.
// Exports: MessageLoadResult and InboxStore message-detail accessors.
// Dependencies: HibossKit MessageDetail, HibossAPIError, and InboxStore state.

import Foundation
import HibossKit

enum MessageLoadResult: Equatable {
    case loaded
    case missing
    case failed(String)
}

extension InboxStore {
    func message(for id: MessageID) -> HistoryMessage? {
        history.first { $0.id == id } ?? openedMessages[id]?.message
    }

    func reply(to id: MessageID) -> HistoryMessage? {
        history.first { $0.replyTo == id.rawValue }
            ?? openedMessages[id]?.replies.first
    }

    func loadMessage(_ id: MessageID) async -> MessageLoadResult {
        guard let api else {
            return .failed(String(localized: "Connection isn't ready."))
        }
        do {
            let detail = try await api.fetchMessage(id)
            guard detail.message.id == id else {
                return .failed(String(localized: "The server returned the wrong message."))
            }
            openedMessages[id] = detail
            return .loaded
        } catch let error as HibossAPIError {
            if case .requestFailed(status: 404, message: _) = error { return .missing }
            return .failed(error.localizedDescription)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
