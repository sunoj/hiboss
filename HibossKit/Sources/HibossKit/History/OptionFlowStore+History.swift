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
