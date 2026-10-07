// Uncached message loading, missing-item and transport-error presentations.
// Exports MessageDetailView fallback helpers; notification lookup remains independent of history.
// Dependencies: SwiftUI, HibossKit, InboxStore and PendingStateView.

import HibossKit
import SwiftUI

extension MessageDetailView {
    /// Shown while the message hasn't landed in history. Holds a spinner until the
    /// store is connected and a clean refresh has run — a live-stream arrival or a
    /// successful fetch re-renders into the message branch above. Only a genuinely
    /// absent message (after a clean load) or exhausted retries shows "not found".
    @ViewBuilder var fallbackView: some View {
        switch fallback {
        case .loading:
            ScrollView {
                PendingStateView(
                    title: String(localized: "Loading message…"), showsPlaceholder: true,
                    onRetry: restartLookup
                ).padding(16)
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Loading…")
                .navigationBarTitleDisplayMode(.inline)
                .task(id: loadAttempt) { await load() }
        case .missing:
            unavailableView(
                title: String(localized: "Message not found"),
                icon: "questionmark.circle",
                description: String(localized: "It may have been cleared or expired.")
            )
        case .failed(let reason):
            unavailableView(
                title: String(localized: "Couldn't load message"),
                icon: "wifi.exclamationmark",
                description: reason
            )
        }
    }

    private func unavailableView(title: String, icon: String, description: String) -> some View {
        ContentUnavailableView {
            Label { Text(verbatim: title) } icon: { Image(systemName: icon) }
        } description: {
            Text(verbatim: description)
        } actions: {
            RetryButton(action: restartLookup)
        }
    }

    private func restartLookup() async {
        fallback = .loading
        loadAttempt += 1
    }

    /// Waits briefly for restored credentials, then fetches only the notification
    /// target. Full history may continue loading independently in the background.
    private func load() async {
        if store.message(for: messageID) != nil { return }
        for _ in 0..<AppConstants.API.notificationReadinessChecks where !store.isReady {
            try? await Task.sleep(for: AppConstants.API.notificationReadinessDelay)
            if Task.isCancelled { return }
        }
        guard store.isReady else {
            fallback = .failed(String(localized: "Connection isn't ready."))
            return
        }
        let result = await store.loadMessage(messageID)
        guard !Task.isCancelled else { return }
        switch result {
        case .loaded:
            break
        case .missing:
            fallback = .missing
        case .failed(let reason):
            fallback = .failed(reason)
        }
    }

}
