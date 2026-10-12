// Compact refresh feedback with fixed geometry for cached native surfaces.
// Exports CompactRefreshNotice; delayed progress and escalation stay inside one status row.
// Dependencies: SwiftUI, PendingTiming, RetryButton, and semantic Theme roles.

import SwiftUI

struct CompactRefreshNotice: View {
    let isRefreshing: Bool
    var error: String? = nil
    let title: String
    var onRetry: (() async -> Void)? = nil
    var statusIdentifier = "refresh-status"
    var retryIdentifier = "pending-retry"
    @State private var visible = false
    @State private var slow = false

    private var active: Bool { error != nil || (isRefreshing && visible) }

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().opacity(isRefreshing && visible && error == nil && !slow ? 1 : 0)
                .accessibilityHidden(!isRefreshing || !visible || error != nil || slow)
            Text(verbatim: error ?? (slow
                ? String(localized: "This is taking longer than expected.") : title))
                .font(.footnote).foregroundStyle(Theme.ink2).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(statusIdentifier)
            if let onRetry {
                RetryButton(action: onRetry).accessibilityIdentifier(retryIdentifier)
                    .opacity(error != nil || slow ? 1 : 0)
                    .allowsHitTesting(error != nil || slow)
                    .accessibilityHidden(error == nil && !slow)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(.bar)
        .opacity(active ? 1 : 0)
        .allowsHitTesting(active)
        .accessibilityHidden(!active)
        .task(id: isRefreshing) {
            visible = false
            slow = false
            guard isRefreshing else { return }
            do {
                try await Task.sleep(for: PendingTiming.revealDelay)
                visible = true
                try await Task.sleep(for: PendingTiming.escalationDelay)
                slow = true
            } catch { return }
        }
    }
}
