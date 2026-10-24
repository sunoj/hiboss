// Row thumbnails: disk cache, then the stored server thumbnail, else a backfill from the original.
// Backfill generates the shared JPEG and PUTs it once per item; 404/405 turns it off for the session.
// Dependencies: HibossKit BoxThumbnailServing and BoxThumbnailGenerator, UIKit.

import HibossKit
import UIKit

extension BoxMediaStore {
    /// Loads a row image; a failure retries here once its backoff elapses. Callers that all
    /// disappear cancel work still queued for a download slot.
    func loadThumbnail(_ item: BoxItem) async {
        guard item.hasMedia, item.kind == .image || item.kind == .video, thumbnails[item.id] == nil
        else { return }
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
            let (image, generated) = try await thumbnailImage(item)
            try Task.checkCancellation()
            thumbnails[item.id] = image
            thumbnailErrors[item.id] = nil
            thumbnailFailures.clear(item.id)
            if let generated { await backfill(generated, for: item) }
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            thumbnailErrors[item.id] = error.localizedDescription
            thumbnailFailures.record(item, now: now())
        }
    }

    /// The image and, when it was made here from the original, the JPEG to backfill.
    private func thumbnailImage(_ item: BoxItem) async throws -> (UIImage, Data?) {
        if let data = await cache?.data(for: item.id), let image = UIImage(data: data) { return (image, nil) }
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
        let url = try await original(item).url
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

    private func backfill(_ data: Data, for item: BoxItem) async {
        guard backfillEnabled, let server = api as? any BoxThumbnailServing,
              backfilled.insert(item.id).inserted else { return }
        do {
            _ = try await server.uploadBoxThumbnail(
                id: item.id, data: data, contentType: BoxThumbnailGenerator.contentType)
        } catch let HibossAPIError.requestFailed(status, _) where status == 404 || status == 405 {
            backfillEnabled = false
        } catch {}
    }
}
