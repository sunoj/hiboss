// Authenticated Box originals in isolated temporary directories, plus bounded row thumbnails.
// Exports: BoxBrowserMedia; originals and thumbnails share a 4-slot download limiter.
// Dependencies: AppKit, Combine, HibossKit, BoxMediaLimiter, BoxThumbnailCache and BoxLoadFailures.

import AppKit
import Combine
import HibossKit
import UniformTypeIdentifiers

@MainActor
final class BoxBrowserMedia: ObservableObject {
    @Published private(set) var files: [String: URL] = [:]
    @Published private(set) var errors: [String: String] = [:]
    @Published var thumbnailErrors: [String: String] = [:]
    /// Decoded row thumbnails; the cost limit bounds memory and an evicted image reloads from disk.
    let images = NSCache<NSString, NSImage>()
    let limiter: BoxMediaLimiter
    let cache: BoxThumbnailCache?
    let now: () -> Date
    let apiProvider: BoxBrowserStore.Provider
    private(set) var generation = 0
    var thumbnailTasks: [String: (task: Task<Void, Never>, waiters: Int)] = [:]
    var thumbnailFailures = BoxLoadFailures()
    /// Off for the rest of the app session once a server answers 405 (no thumbnail route).
    var backfillEnabled = true
    var backfilled: Set<String> = []
    /// Rows and detail panes currently on screen, counted per item.
    var visible: [String: (item: BoxItem, count: Int)] = [:]
    private var tasks: [String: Task<URL?, Never>] = [:]
    private var observations: [AnyCancellable] = []

    init(apiProvider: @escaping BoxBrowserStore.Provider, cache: BoxThumbnailCache? = nil,
         concurrency: Int = 4, now: @escaping () -> Date = { Date() }) {
        self.apiProvider = apiProvider
        self.cache = cache
        self.limiter = BoxMediaLimiter(limit: concurrency)
        self.now = now
        images.totalCostLimit = 96 * 1024 * 1024
        observations.append(AccountAuthorization.shared.observe { [weak self] _ in self?.reset() })
        observations.append(NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in Task { @MainActor in await self?.retryFailedLoads() } })
    }

    func reset() {
        generation += 1
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        thumbnailTasks.values.forEach { $0.task.cancel() }
        thumbnailTasks = [:]
        for id in files.keys { removeFile(id) }
        errors = [:]
        thumbnailErrors = [:]
        thumbnailFailures = BoxLoadFailures()
        images.removeAllObjects()
        objectWillChange.send()
    }

    /// Forgets a removed item everywhere, including its cached thumbnail on disk.
    func remove(id: String) {
        tasks[id]?.cancel()
        thumbnailTasks[id]?.task.cancel()
        thumbnailTasks[id] = nil
        removeFile(id)
        errors[id] = nil
        thumbnailErrors[id] = nil
        thumbnailFailures.clear(id)
        images.removeObject(forKey: id as NSString)
        objectWillChange.send()
        if let cache { Task { await cache.remove(id) } }
    }

    /// The original for viewers, Quick Look, copy and share; nil with `errors[id]` on failure.
    func load(_ item: BoxItem) async -> URL? {
        guard item.hasMedia else { return nil }
        if let file = files[item.id] { return file }
        if let task = tasks[item.id] { return await task.value }
        let current = generation
        let task = Task { () -> URL? in
            do { return try await self.download(item, generation: current) } catch {
                if current == self.generation, !Task.isCancelled, !(error is CancellationError) {
                    self.errors[item.id] = error.localizedDescription
                }
                return nil
            }
        }
        tasks[item.id] = task
        let file = await task.value
        if generation == current, tasks[item.id] == task { tasks[item.id] = nil }
        return file
    }

    /// Downloads the original again, e.g. when a viewer could not decode the cached copy.
    func reload(_ item: BoxItem) async -> URL? {
        if tasks[item.id] == nil { removeFile(item.id) }
        errors[item.id] = nil
        return await load(item)
    }

    /// The original for a row's thumbnail: a viewer's copy when one exists, otherwise a private
    /// download (`owned`) that the caller deletes. It leaves the limiter queue when cancelled.
    func rowOriginal(_ item: BoxItem) async throws -> (url: URL, owned: Bool) {
        if let file = files[item.id] { return (file, false) }
        if let task = tasks[item.id] {
            if let file = await task.value { return (file, false) }
            throw BoxBrowserError.media(errors[item.id] ?? L("Couldn't open this item."))
        }
        return (try await fetch(item), true)
    }

    func referenceFile(_ item: BoxItem) throws -> URL {
        if let file = files[item.id] { return file }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = String(item.displayTitle.prefix(80)).replacingOccurrences(of: "/", with: "-")
        let file = directory.appendingPathComponent(name + (item.kind == .link ? ".webloc" : ".txt"))
        do {
            if item.kind == .link {
                let data = try PropertyListSerialization.data(fromPropertyList: ["URL": item.url ?? ""],
                    format: .xml, options: 0)
                try data.write(to: file)
            } else { try (item.text ?? "").write(to: file, atomically: true, encoding: .utf8) }
            files[item.id] = file
            return file
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private func removeFile(_ id: String) {
        if let file = files.removeValue(forKey: id) {
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        }
    }

    private func download(_ item: BoxItem, generation current: Int) async throws -> URL {
        let file = try await fetch(item)
        guard current == generation, !Task.isCancelled else {
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
            throw CancellationError()
        }
        if let existing = files[item.id] {
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
            return existing
        }
        files[item.id] = file
        errors[item.id] = nil
        return file
    }

    /// Downloads into a new temporary directory that the caller owns.
    private func fetch(_ item: BoxItem) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let ext = item.mediaType.flatMap { UTType(mimeType: $0)?.preferredFilenameExtension } ?? "bin"
        var name = ((item.text ?? "attachment") as NSString).lastPathComponent
        if name.isEmpty || name == "." || name == ".." { name = "attachment" }
        if (name as NSString).pathExtension.isEmpty { name += ".\(ext)" }
        let file = directory.appendingPathComponent(name)
        do {
            guard let api = apiProvider() else { throw BoxBrowserError.notConfigured }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let id = item.id
            try await limiter.run { try await api.downloadBoxMedia(id: id, to: file) }
            try Task.checkCancellation()
            return file
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}
