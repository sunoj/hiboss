// Row thumbnails: disk cache, then the stored server thumbnail, else a backfill from the original.
// Backfill generates the shared JPEG and PUTs it once per item; 405 turns it off for the app session.
// Dependencies: AppKit, ImageIO, HibossKit BoxThumbnailServing and BoxThumbnailGenerator.

import AppKit
import HibossKit
import ImageIO

extension BoxBrowserMedia {
    func thumbnail(_ id: String) -> NSImage? { images.object(forKey: id as NSString) }

    /// Loads a row image; a failure retries here once its backoff elapses. Callers that all
    /// disappear cancel work still queued for a download slot.
    func loadThumbnail(_ item: BoxItem) async {
        guard item.hasImageMedia || (item.hasMedia && item.kind == .video), thumbnail(item.id) == nil
        else { return }
        if thumbnailErrors[item.id] != nil {
            guard thumbnailFailures.canRetry(item.id, now: now()) else { return }
            thumbnailErrors[item.id] = nil
        }
        let current = generation
        let task = thumbnailTasks[item.id]?.task ?? Task { await self.fetchThumbnail(item, generation: current) }
        thumbnailTasks[item.id] = (task, (thumbnailTasks[item.id]?.waiters ?? 0) + 1)
        await withTaskCancellationHandler { await task.value } onCancel: {
            Task { @MainActor in self.leave(item.id, task: task, cancelled: true) }
        }
        if !Task.isCancelled { leave(item.id, task: task, cancelled: false) }
    }

    /// The manual retry: skips the backoff and starts a fresh attempt.
    func retryThumbnail(_ item: BoxItem) async {
        thumbnailTasks[item.id]?.task.cancel()
        thumbnailTasks[item.id] = nil
        thumbnailErrors[item.id] = nil
        thumbnailFailures.clear(item.id)
        await loadThumbnail(item)
    }

    /// Retries every visible failed row whose backoff has elapsed, e.g. when the app becomes active.
    func retryFailedLoads() async {
        let due = thumbnailFailures.due(now: now()).filter { visible[$0.id] != nil }
        await withTaskGroup(of: Void.self) { group in
            for item in due { group.addTask { await self.loadThumbnail(item) } }
        }
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

    private func fetchThumbnail(_ item: BoxItem, generation current: Int) async {
        do {
            let (image, generated) = try await thumbnailImage(item)
            try Task.checkCancellation()
            guard current == generation else { return }
            images.setObject(image.image, forKey: item.id as NSString, cost: image.cost)
            thumbnailErrors[item.id] = nil
            thumbnailFailures.clear(item.id)
            objectWillChange.send()
            if let generated { await backfill(generated, for: item) }
        } catch {
            guard current == generation, !Task.isCancelled, !(error is CancellationError) else { return }
            thumbnailErrors[item.id] = error.localizedDescription
            thumbnailFailures.record(item, now: now())
        }
    }

    /// The decoded image and, when it was made here from the original, the JPEG to backfill.
    private func thumbnailImage(_ item: BoxItem) async throws -> (DecodedThumbnail, Data?) {
        if let data = await cache?.data(for: item.id), let image = await Self.decode(data) {
            return (image, nil)
        }
        if item.hasThumbnail, let api = apiProvider() {
            do {
                let id = item.id
                let data = try await limiter.run { try await api.downloadBoxThumbnail(id: id) }
                if let image = await Self.decode(data) {
                    await cache?.store(data, for: item.id)
                    return (image, nil)
                }
            } catch let HibossAPIError.requestFailed(status, _) where status == 404 {}
        }
        let original = try await rowOriginal(item)
        defer {
            if original.owned { try? FileManager.default.removeItem(at: original.url.deletingLastPathComponent()) }
        }
        return try await generate(item, from: original.url)
    }

    /// The shared JPEG (cached, and backfilled for image and video kinds) or, when it exceeds the
    /// size limit, a downsampled image; never a full-resolution decode.
    private func generate(_ item: BoxItem, from url: URL) async throws -> (DecodedThumbnail, Data?) {
        let kind: BoxItem.Kind = item.kind == .video ? .video : .image
        if let data = await Task.detached(operation: {
               await BoxThumbnailGenerator.thumbnail(for: url, kind: kind)
           }).value, let image = await Self.decode(data) {
            await cache?.store(data, for: item.id)
            return (image, item.kind == .image || item.kind == .video ? data : nil)
        }
        guard item.hasImageMedia, let image = await Task.detached(operation: {
            BoxThumbnailGenerator.downsample(url, maxPixelSize: BoxThumbnailGenerator.maxPixelSize)
        }).value else { throw HibossAPIError.invalidResponse }
        return (DecodedThumbnail(image), nil)
    }

    private func backfill(_ data: Data, for item: BoxItem) async {
        guard backfillEnabled, let api = apiProvider(), backfilled.insert(item.id).inserted else { return }
        do {
            _ = try await api.uploadBoxThumbnail(
                id: item.id, data: data, contentType: BoxThumbnailGenerator.contentType)
        } catch let HibossAPIError.requestFailed(status, _) where status == 405 {
            backfillEnabled = false
        } catch {}
    }

    /// Decodes off the main actor so drawing a row never decodes the JPEG lazily.
    nonisolated private static func decode(_ data: Data) async -> DecodedThumbnail? {
        await Task.detached {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, [
                      kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { return nil }
            return DecodedThumbnail(image)
        }.value
    }
}

struct DecodedThumbnail: @unchecked Sendable {
    let image: NSImage
    let cost: Int

    init(_ image: CGImage) {
        self.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        cost = image.bytesPerRow * image.height
    }
}
