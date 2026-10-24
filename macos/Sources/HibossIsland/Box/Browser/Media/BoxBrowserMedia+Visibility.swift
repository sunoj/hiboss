// Visible Box rows: a stable task id, manual and activation retries, and a load loop that retries
// each failure when its backoff ends and reloads after a reset, so a row recovers without scrolling.
// Dependencies: HibossKit BoxItem and BoxBrowserMedia's thumbnail jobs.

import Foundation
import HibossKit

extension BoxBrowserMedia {
    /// The row and detail `.task` id: it changes only when the image leaves memory, never when it
    /// appears, so a load's own publish cannot cancel it.
    func thumbnailTaskID(_ id: String) -> String { "\(id)#\(thumbnailEpochs[id] ?? 0)" }

    /// The manual retry: skips the backoff and starts a fresh attempt.
    func retryThumbnail(_ item: BoxItem) async {
        cancelLoad(item.id)
        thumbnailErrors[item.id] = nil
        thumbnailFailures.clear(item.id)
        await loadThumbnail(item)
    }

    /// Retries every visible failed row whose backoff has elapsed, e.g. when the app becomes active.
    func retryFailedLoads() {
        for item in thumbnailFailures.due(now: now()) where visible[item.id] != nil {
            Task { await loadThumbnail(item) }
        }
    }

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
