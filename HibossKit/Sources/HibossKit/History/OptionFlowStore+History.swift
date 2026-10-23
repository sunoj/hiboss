// Reconciles live option presentation with authoritative history resolutions.
// Extends OptionFlowStore without deriving answerability from cached rows.
// Depends on shared history messages and OptionResolution.

import Foundation

extension OptionFlowStore {
    /// Dismiss any shown/queued option the freshly-loaded history now marks
    /// resolved. Unlike the derived iOS inbox, this store holds `activeMessage`
    /// imperatively, so without this a card answered elsewhere while our stream
    /// was reconnecting would linger until its local expiry.
    func reconcileActiveAgainstHistory() {
        func resolvedInHistory(_ id: MessageID) -> HistoryMessage? {
            historyMessages.first { $0.id == id && ($0.status == "replied" || $0.status == "expired") }
        }
        queuedMessages.removeAll { resolvedInHistory($0.id) != nil }
        guard let active = activeMessage, let resolved = resolvedInHistory(active.id) else { return }
        // Already showing the resolved card for this id — don't restart its linger
        // on a subsequent history refresh.
        if case .resolved = presentationState { return }
        let reply = historyMessages.first { $0.replyTo == active.id.rawValue }
        resolve(OptionResolution(
            id: active.id,
            status: resolved.status == "expired" ? .expired : .replied,
            answer: reply?.body,
            source: reply?.metadata?.source,
            answeredBy: reply?.metadata?.answeredBy
        ))
    }

}

extension OptionFlowStore {
    /// Asks the server about every shown or queued option on each stream (re)connect. The
    /// stream replays only recent resolutions and history keeps only the newest rows, so an
    /// ask that closed while this client was offline would otherwise stay until its deadline.
    func reconcileShownAsks() {
        guard let api else { return }
        let ids = (activeMessage.map { [$0.id] } ?? []) + queuedMessages.map(\.id)
        guard !ids.isEmpty else { return }
        let version = historyVersion
        Task { [weak self] in
            for id in ids {
                // An unreachable lookup keeps the ask; its local deadline still bounds it.
                guard let detail = try? await api.fetchMessage(id) else { continue }
                guard let self, version == self.historyVersion else { return }
                guard let resolution = Self.closedResolution(detail) else { continue }
                if self.activeMessage?.id == id, case .resolved = self.presentationState { continue }
                self.resolve(resolution)
            }
        }
    }

    /// The resolution a message detail implies, or nil while the ask is still open.
    nonisolated static func closedResolution(_ detail: MessageDetail, now: Date = .now) -> OptionResolution? {
        let message = detail.message
        if message.status == "replied" {
            let reply = detail.replies.first {
                $0.direction == "boss_to_agent" && $0.replyTo == message.id.rawValue
            }
            return OptionResolution(id: message.id, status: .replied, answer: reply?.body,
                                    source: reply?.metadata?.source, answeredBy: reply?.metadata?.answeredBy)
        }
        let expired = message.status == "expired" || message.metadata?.isExpired == true
            || message.expirationDate.map { $0 <= now } == true
        return expired ? OptionResolution(id: message.id, status: .expired) : nil
    }
}
