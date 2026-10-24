// Visible Box rows: activation retries cover them, and a failed visible row retries once when
// its backoff ends, so it recovers without scrolling.
// Dependencies: HibossKit BoxItem and BoxBrowserMedia's thumbnail loading.

import Foundation
import HibossKit

extension BoxBrowserMedia {
    /// Runs for as long as a row or detail pane shows `item`; call it from the view's `.task`.
    func show(_ item: BoxItem) async {
        visible[item.id] = (item, (visible[item.id]?.count ?? 0) + 1)
        defer { hide(item.id) }
        await loadThumbnail(item)
        if thumbnailErrors[item.id] != nil, let retryAt = thumbnailFailures.retryAt(item.id) {
            try? await Task.sleep(for: .seconds(max(0, retryAt.timeIntervalSince(now()))))
            if !Task.isCancelled { await loadThumbnail(item) }
        }
        while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
    }

    private func hide(_ id: String) {
        guard let entry = visible[id] else { return }
        visible[id] = entry.count <= 1 ? nil : (entry.item, entry.count - 1)
    }
}
