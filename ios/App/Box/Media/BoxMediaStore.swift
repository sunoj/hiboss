// Authenticated Box originals for viewers and small thumbnails for rows, behind one download cap.
// Exports BoxMediaStore and BoxMediaResource; temporary bytes are removed with their resource.
// Dependencies: HibossKit, Combine, UIKit, BoxMediaLimiter, BoxThumbnailCache and BoxLoadFailures.

import Combine
import HibossKit
import UIKit

final class BoxMediaResource {
    let url: URL
    private let directory: URL?

    init(url: URL, directory: URL? = nil) {
        self.url = url
        self.directory = directory
    }

    deinit { try? FileManager.default.removeItem(at: directory ?? url) }
}

@MainActor
final class BoxMediaStore: ObservableObject {
    @Published private(set) var resources: [String: BoxMediaResource] = [:]
    @Published private(set) var errors: [String: String] = [:]
    @Published var thumbnails: [String: UIImage] = [:]
    @Published var thumbnailErrors: [String: String] = [:]
    let api: (any BoxServing)?
    let limiter: BoxMediaLimiter
    let cache: BoxThumbnailCache?
    let now: () -> Date
    var thumbnailTasks: [String: (task: Task<Void, Never>, waiters: Int)] = [:]
    var thumbnailFailures = BoxLoadFailures()
    var backfillEnabled = true
    var backfilled: Set<String> = []
    private var tasks: [String: Task<Void, Never>] = [:]
    private var failures = BoxLoadFailures()

    init(api: (any BoxServing)?, cache: BoxThumbnailCache? = .standard, concurrency: Int = 4,
         now: @escaping () -> Date = { Date() }) {
        self.api = api
        self.cache = cache
        self.limiter = BoxMediaLimiter(limit: concurrency)
        self.now = now
    }

    /// Downloads the original for viewers, copy and share; a failure waits out its backoff.
    func load(_ item: BoxItem) async {
        guard item.hasMedia, resources[item.id] == nil else { return }
        if errors[item.id] != nil {
            guard failures.canRetry(item.id, now: now()) else { return }
            errors[item.id] = nil
        }
        if let task = tasks[item.id] { return await task.value }
        let task = Task {
            do { _ = try await self.download(item) } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                self.errors[item.id] = error.localizedDescription
                self.failures.record(item, now: self.now())
            }
        }
        tasks[item.id] = task
        await task.value
        if tasks[item.id] == task { tasks[item.id] = nil }
    }

    func retry(_ item: BoxItem) async {
        tasks[item.id]?.cancel()
        await tasks[item.id]?.value
        tasks[item.id] = nil
        errors[item.id] = nil
        failures.clear(item.id)
        await load(item)
    }

    /// Retries every failed load whose backoff has elapsed, e.g. when the app returns to the foreground.
    func retryFailedLoads() async {
        let originals = failures.due(now: now())
        let rows = thumbnailFailures.due(now: now())
        await withTaskGroup(of: Void.self) { group in
            for item in originals { group.addTask { await self.load(item) } }
            for item in rows { group.addTask { await self.loadThumbnail(item) } }
        }
    }

    func loadSelection(id: String, items: [BoxItem]) async {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        for position in [index, index + 1, index - 1] where items.indices.contains(position) {
            guard !Task.isCancelled else { return }
            await load(items[position])
        }
    }

    func remove(id: String) {
        tasks[id]?.cancel()
        thumbnailTasks[id]?.task.cancel()
        resources[id] = nil
        errors[id] = nil
        thumbnails[id] = nil
        thumbnailErrors[id] = nil
        failures.clear(id)
        thumbnailFailures.clear(id)
        if let cache { Task { await cache.remove(id) } }
    }

    /// The downloaded original, reusing a finished or in-flight viewer download.
    func original(_ item: BoxItem) async throws -> BoxMediaResource {
        if let resource = resources[item.id] { return resource }
        if let task = tasks[item.id], !Task.isCancelled {
            await task.value
            if let resource = resources[item.id] { return resource }
        }
        return try await download(item)
    }

    private func download(_ item: BoxItem) async throws -> BoxMediaResource {
        guard let api else { throw CancellationError() }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("box-\(UUID().uuidString)")
        let pending = directory.appendingPathComponent("download")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let id = item.id
            try await limiter.run { try await api.downloadBoxMedia(id: id, to: pending) }
            let url = directory.appendingPathComponent(try BoxDownloadName.filename(item, bytesAt: pending))
            if url != pending { try FileManager.default.moveItem(at: pending, to: url) }
            try Task.checkCancellation()
            let resource = BoxMediaResource(url: url, directory: directory)
            resources[item.id] = resource
            errors[item.id] = nil
            failures.clear(item.id)
            return resource
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}
