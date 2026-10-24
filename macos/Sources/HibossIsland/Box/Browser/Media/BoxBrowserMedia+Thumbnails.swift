// Row thumbnails: one store-owned job per item reads the disk cache, the stored server thumbnail
// or the original, publishes the image to waiting rows, then PUTs a backfill JPEG in a limiter
// slot under BoxBackfillSession rules. Dependencies: AppKit, ImageIO, HibossKit generator.

import AppKit
import HibossKit
import ImageIO

/// One item's load. Rows wait only until it publishes; the PUT after that belongs to the store.
@MainActor
final class BoxThumbnailJob {
    var task: Task<Void, Never>?
    var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
}

extension BoxBrowserMedia {
    func thumbnail(_ id: String) -> NSImage? { images[id] }

    static func hasThumbnailSource(_ item: BoxItem) -> Bool {
        item.hasImageMedia || (item.hasMedia && item.kind == .video)
    }

    /// Waits until the item's image is published or its load ends; a failure retries here once its
    /// backoff elapses. A leaving row stops waiting, and the last one cancels an unpublished load.
    func loadThumbnail(_ item: BoxItem) async {
        guard Self.hasThumbnailSource(item), thumbnail(item.id) == nil else { return }
        if thumbnailErrors[item.id] != nil {
            guard thumbnailFailures.canRetry(item.id, now: now()) else { return }
            thumbnailErrors[item.id] = nil
        }
        let job = thumbnailTasks[item.id] ?? startJob(item), key = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { job.waiters[key] = $0 }
        } onCancel: {
            Task { @MainActor in
                guard self.thumbnailTasks[item.id] === job, let waiter = job.waiters.removeValue(forKey: key)
                else { return }
                waiter.resume()
                if job.waiters.isEmpty { self.cancelLoad(item.id) }
            }
        }
    }

    /// Cancels a load that has not published and wakes its rows; a PUT in progress is not reached.
    func cancelLoad(_ id: String) {
        thumbnailTasks[id]?.task?.cancel()
        thumbnailTasks[id].map { finish($0, id) }
    }

    /// The job captures the client and the account generation once, for its load and its PUT.
    private func startJob(_ item: BoxItem) -> BoxThumbnailJob {
        let job = BoxThumbnailJob(), api = apiProvider(), current = generation
        job.task = Task { await self.run(job, item, api: api, generation: current) }
        thumbnailTasks[item.id] = job
        return job
    }

    /// Publishes the image, wakes the rows, then makes the backfill PUT in a limiter slot: one per
    /// item at a time, never sent once a reset has made the job's generation stale.
    private func run(_ job: BoxThumbnailJob, _ item: BoxItem, api: (any BoxBrowsing)?,
                     generation current: Int) async {
        defer { finish(job, item.id) }
        let id = item.id, loaded: (image: DecodedThumbnail, backfill: Data?)
        do {
            loaded = try await thumbnailImage(item, api: api)
            try Task.checkCancellation()
        } catch {
            guard current == generation, !Task.isCancelled, !(error is CancellationError) else { return }
            thumbnailErrors[id] = error.localizedDescription
            thumbnailFailures.record(item, now: now())
            return
        }
        guard current == generation else { return }
        objectWillChange.send()
        images.set(loaded.image.image, cost: loaded.image.cost, for: id)
        thumbnailErrors[id] = nil
        thumbnailFailures.clear(id)
        finish(job, id)
        guard let data = loaded.backfill, let api, uploads[id] == nil, backfill.begin(id) else { return }
        uploads[id] = job
        defer { if uploads[id] === job { uploads[id] = nil } }
        do {
            try await limiter.run { @MainActor in
                guard current == self.generation else { throw CancellationError() }
                _ = try await api.uploadBoxThumbnail(
                    id: id, data: data, contentType: BoxThumbnailGenerator.contentType)
            }
            backfill.succeeded(id)
        } catch { if current == generation { backfill.failed(id, error: error) } }
    }

    /// Wakes the job's rows; later calls do nothing.
    private func finish(_ job: BoxThumbnailJob, _ id: String) {
        if thumbnailTasks[id] === job { thumbnailTasks[id] = nil }
        job.waiters.values.forEach { $0.resume() }
        job.waiters = [:]
    }

    /// The decoded image and, when the server has no thumbnail yet, the JPEG made here to backfill.
    private func thumbnailImage(_ item: BoxItem, api: (any BoxBrowsing)?) async throws
        -> (DecodedThumbnail, Data?) {
        if let data = await cache?.data(for: item.id), let image = await Self.decode(data) {
            return (image, item.hasThumbnail ? nil : data)
        }
        if item.hasThumbnail, let api {
            do {
                let id = item.id
                let data = try await limiter.run { try await api.downloadBoxThumbnail(id: id) }
                if let image = await Self.decode(data) {
                    await cache?.store(data, for: item.id)
                    return (image, nil)
                }
            } catch let HibossAPIError.requestFailed(status, _) where status == 404 {}
        }
        let original = try await rowOriginal(item, api: api)
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
