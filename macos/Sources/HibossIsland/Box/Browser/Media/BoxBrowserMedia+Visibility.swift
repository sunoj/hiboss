// Visible Box rows: activation retries cover them, and a visible row retries each failure when
// its backoff ends and reloads after a reset, so it recovers without scrolling.
// Dependencies: HibossKit BoxItem and BoxBrowserMedia's thumbnail loading.

import Foundation
import HibossKit

extension BoxBrowserMedia {
    /// A row's or detail pane's load task: loads the image and, while it stays on screen, retries
    /// each failure once its backoff ends and reloads after a reset. The view cancels it on leaving.
    func show(_ item: BoxItem) async {
        visible[item.id] = (item, (visible[item.id]?.count ?? 0) + 1)
        defer { hide(item.id) }
        while !Task.isCancelled {
            let started = generation
            await loadThumbnail(item)
            guard Self.hasThumbnailSource(item), thumbnail(item.id) == nil else { return }
            if thumbnailErrors[item.id] != nil, let retryAt = thumbnailFailures.retryAt(item.id) {
                try? await Task.sleep(for: .seconds(max(0, retryAt.timeIntervalSince(now()))))
            } else if thumbnailTasks[item.id] == nil, generation == started {
                return
            }
        }
    }

    private func hide(_ id: String) {
        guard let entry = visible[id] else { return }
        visible[id] = entry.count <= 1 ? nil : (entry.item, entry.count - 1)
    }
}
