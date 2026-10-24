// Row thumbnails: memory, disk cache, the stored server thumbnail, else a backfill from the original.
// A visible row retries each failure when its backoff ends; PUTs follow BoxBackfillSession.
// Dependencies: HibossKit BoxThumbnailServing and BoxThumbnailGenerator, UIKit.

import HibossKit
import UIKit

extension BoxMediaStore {
    /// A row's load task: loads the image and, while the row stays on screen, retries each
    /// failure once its backoff ends. The row cancels it when it disappears.
    func showThumbnail(_ item: BoxItem) async {
        visibleRows[item.id] = (item, (visibleRows[item.id]?.count ?? 0) + 1)
        defer { hide(item.id) }
        while !Task.isCancelled {
            await loadThumbnail(item)
            guard Self.hasThumbnailSource(item), thumbnail(item.id) == nil else { return }
            if thumbnailErrors[item.id] != nil, let retryAt = thumbnailFailures.retryAt(item.id) {
                let delay = max(0, retryAt.timeIntervalSince(now()))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } else if thumbnailTasks[item.id] == nil {
                return
            }
        }
    }

    /// Loads a row image; a failure retries here once its backoff elapses. Callers that all
    /// disappear cancel work still queued for a download slot.
    func loadThumbnail(_ item: BoxItem) async {
        guard Self.hasThumbnailSource(item), memory[item.id] == nil else { return }
        if thumbnailErrors[item.id] != nil {
            guard thumbnailFailures.canRetry(item.id, now: now()) else { return }
            thumbnailErrors[item.id] = nil
        }
        let task = thumbnailTasks[item.id]?.task ?? Task { await self.fetchThumbnail(item) }
        thumbnailTasks[item.id] = (task, (thumbnailTasks[item.id]?.waiters ?? 0) + 1)
        await withTaskCancellationHandler { await task.value } onCancel: {
            Task { @MainActor in self.leave(item.id, task: task, cancelled: true) }
        }
        leave(item.id, task: task, cancelled: false)
    }

    func retryThumbnail(_ item: BoxItem) async {
        thumbnailTasks[item.id]?.task.cancel()
        thumbnailTasks[item.id] = nil
        thumbnailErrors[item.id] = nil
        thumbnailFailures.clear(item.id)
        await loadThumbnail(item)
    }

    private static func hasThumbnailSource(_ item: BoxItem) -> Bool {
        item.hasMedia && (item.kind == .image || item.kind == .video)
    }

    private func hide(_ id: String) {
        guard let entry = visibleRows[id] else { return }
        visibleRows[id] = entry.count > 1 ? (entry.item, entry.count - 1) : nil
    }

    private func leave(_ id: String, task: Task<Void, Never>, cancelled: Bool) {
        guard let entry = thumbnailTasks[id], entry.task == task else { return }
        if entry.waiters <= 1 {
            thumbnailTasks[id] = nil
            if cancelled { task.cancel() }
        } else {
            thumbnailTasks[id] = (task, entry.waiters - 1)
        }
    }

    private func fetchThumbnail(_ item: BoxItem) async {
        do {
            let (image, unstored) = try await thumbnailImage(item)
            try Task.checkCancellation()
            objectWillChange.send()
            memory.set(image, for: item.id)
            thumbnailErrors[item.id] = nil
            thumbnailFailures.clear(item.id)
            if let unstored { await upload(unstored, for: item) }
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            thumbnailErrors[item.id] = error.localizedDescription
            thumbnailFailures.record(item, now: now())
        }
    }

    /// The image and, when the server has no thumbnail yet, the JPEG made here to backfill.
    private func thumbnailImage(_ item: BoxItem) async throws -> (UIImage, Data?) {
        if let data = await cache?.data(for: item.id), let image = UIImage(data: data) {
            return (image, item.hasThumbnail ? nil : data)
        }
        if item.hasThumbnail, let server = api as? any BoxThumbnailServing {
            do {
                let id = item.id
                let data = try await limiter.run { try await server.downloadBoxThumbnail(id: id) }
                if let image = UIImage(data: data) {
                    await cache?.store(data, for: item.id)
                    return (image, nil)
                }
            } catch let HibossAPIError.requestFailed(status, _) where status == 404 {}
        }
        let resource = try await original(item)
        defer { withExtendedLifetime(resource) {} }
        let url = resource.url
        if let data = await BoxThumbnailGenerator.thumbnail(for: url, kind: item.kind),
           let image = UIImage(data: data) {
            await cache?.store(data, for: item.id)
            return (image, data)
        }
        guard item.kind == .image, let image = await Task.detached(operation: {
            BoxThumbnailGenerator.downsample(url, maxPixelSize: BoxThumbnailGenerator.maxPixelSize)
        }).value else { throw HibossAPIError.invalidResponse }
        return (UIImage(cgImage: image), nil)
    }

    private func upload(_ data: Data, for item: BoxItem) async {
        guard let server = api as? any BoxThumbnailServing, backfill.begin(item.id) else { return }
        do {
            _ = try await server.uploadBoxThumbnail(
                id: item.id, data: data, contentType: BoxThumbnailGenerator.contentType)
            backfill.succeeded(item.id)
        } catch {
            backfill.failed(item.id, error: error)
        }
    }
}
