// Sends replies to history messages without applying outcomes from an old connection.
// Exports OptionFlowStore.answerHistory; feedback stays owned by OptionFlowStore.
// Dependencies: BossServing, historyVersion, and the store's history synchronization helpers.

import Foundation

extension OptionFlowStore {
    /// Answers a past (history) option message by id, independent of the live `activeMessage`.
    /// True only when the server accepted this reply; otherwise `replyFeedback[messageID]` says why.
    @discardableResult
    public func answerHistory(_ choice: String, for messageID: MessageID) async -> Bool {
        let version = historyVersion
        guard !Task.isCancelled else { return false }
        guard let api else {
            setHistoryReplyFeedback(.failed(kitL("Disconnected")), for: messageID)
            return false
        }
        setHistoryReplyFeedback(nil, for: messageID)
        do {
            let outcome = try await api.reply(to: messageID, with: choice)
            guard version == historyVersion, !Task.isCancelled else { return false }
            switch outcome {
            case .accepted, .acceptedOn:
                refreshHistoryInBackground()
                return true
            case .alreadyResolved:
                await settleConflict(for: messageID)
                return false
            }
        } catch {
            guard version == historyVersion, !Task.isCancelled else { return false }
            if AccountAuthorization.shared.reject(error) { return false }
            setHistoryReplyFeedback(.failed(error.localizedDescription), for: messageID)
            return false
        }
    }
}
