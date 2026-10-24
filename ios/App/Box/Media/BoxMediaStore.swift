// Authenticated Box originals for viewers and small thumbnails for rows, behind one download cap.
// Exports BoxMediaStore and BoxMediaResource; temporary bytes are removed with their resource.
// Dependencies: HibossKit, Combine, UIKit, the limiter, thumbnail caches, backfill session, failures.

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
    @Published var thumbnailErrors: [String: String] = [:]
    /// Bumped when an id's image leaves memory, so a visible row's load task runs again.
    @Published private(set) var thumbnailEpochs: [String: Int] = [:]
    let api: (any BoxServing)?
    let limiter: BoxMediaLimiter
    let cache: BoxThumbnailCache?
    let memory: BoxThumbnailMemory
    let backfill: BoxBackfillSession
    let now: () -> Date
    var thumbnailTasks: [String: (task: Task<Void, Never>, waiters: Int)] = [:]
    var thumbnailFailures = BoxLoadFailures()
    /// Rows on screen that are still loading or waiting out a failure's backoff.
    var visibleRows: [String: (item: BoxItem, count: Int)] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    private var failures = BoxLoadFailures()
    private var memoryWarning: AnyCancellable?

    init(api: (any BoxServing)?, cache: BoxThumbnailCache? = .standard, concurrency: Int = 4,
         memory: BoxThumbnailMemory = BoxThumbnailMemory(), backfill: BoxBackfillSession = .shared,
         now: @escaping () -> Date = { Date() }) {
        self.api = api
        self.cache = cache
        self.limiter = BoxMediaLimiter(limit: concurrency)
        self.memory = memory
        self.backfill = backfill
        self.now = now
        memory.onEvict = { [weak self] id in Task { @MainActor in self?.thumbnailEvicted(id) } }
        memoryWarning = NotificationCenter.default
            .publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak memory] _ in memory?.removeAll() }
    }

    func thumbnail(_ id: String) -> UIImage? { memory[id] }

    private func thumbnailEvicted(_ id: String) {
        thumbnailEpochs[id, default: 0] += 1
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

    /// Retries the failed rows on screen whose backoff has elapsed, e.g. on return to the foreground.
    func retryFailedLoads() async {
        let rows = visibleRows.values.map(\.item).filter {
            thumbnailErrors[$0.id] != nil && thumbnailFailures.canRetry($0.id, now: now())
        }
        await withTaskGroup(of: Void.self) { group in
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
        memory.remove(id)
        thumbnailErrors[id] = nil
        failures.clear(id)
        thumbnailFailures.clear(id)
        if let cache { Task { await cache.remove(id) } }
    }

    /// The original a viewer requested, or a download only the caller holds; its bytes go when it is freed.
    func original(_ item: BoxItem) async throws -> BoxMediaResource {
        if let resource = resources[item.id] { return resource }
        if let task = tasks[item.id], !Task.isCancelled {
            await task.value
            if let resource = resources[item.id] { return resource }
        }
        return try await download(item, keep: false)
    }

    private func download(_ item: BoxItem, keep: Bool = true) async throws -> BoxMediaResource {
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
            guard keep else { return resource }
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
