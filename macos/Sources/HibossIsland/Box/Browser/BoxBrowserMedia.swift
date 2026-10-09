// Authenticated Box downloads stored in isolated temporary directories for native opening.
// Exports: BoxBrowserMedia with deduplicated downloads and image thumbnails.
// Dependencies: AppKit, ImageIO, UniformTypeIdentifiers and BoxBrowserStore.Provider.

import AppKit
import Combine
import HibossKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class BoxBrowserMedia: ObservableObject {
    @Published private(set) var files: [String: URL] = [:]
    @Published private(set) var thumbnails: [String: NSImage] = [:]
    @Published private(set) var errors: [String: String] = [:]
    private var tasks: [String: Task<URL?, Never>] = [:]
    private var generation = 0
    private let apiProvider: BoxBrowserStore.Provider

    init(apiProvider: @escaping BoxBrowserStore.Provider) { self.apiProvider = apiProvider }

    func reset() {
        generation += 1
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        for id in files.keys { remove(id: id) }
        errors = [:]
    }

    func remove(id: String) {
        tasks[id]?.cancel()
        if let file = files.removeValue(forKey: id) {
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        }
        thumbnails[id] = nil
        errors[id] = nil
    }

    func load(_ item: BoxItem) async -> URL? {
        guard item.hasMedia else { return nil }
        if let file = files[item.id] { return file }
        if let task = tasks[item.id] { return await task.value }
        let current = generation
        let task = Task { await download(item, generation: current) }
        tasks[item.id] = task
        let file = await task.value
        if generation == current { tasks[item.id] = nil }
        return file
    }

    private func download(_ item: BoxItem, generation current: Int) async -> URL? {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let ext = item.mediaType.flatMap { UTType(mimeType: $0)?.preferredFilenameExtension } ?? "bin"
        var name = ((item.text ?? "attachment") as NSString).lastPathComponent
        if name.isEmpty || name == "." || name == ".." { name = "attachment" }
        if (name as NSString).pathExtension.isEmpty { name += ".\(ext)" }
        let file = directory.appendingPathComponent(name)
        do {
            guard let api = apiProvider() else { throw BoxBrowserError.notConfigured }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try await api.downloadBoxMedia(id: item.id, to: file)
            try Task.checkCancellation()
            guard current == generation else { throw CancellationError() }
            if item.hasImageMedia {
                guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 160,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ] as CFDictionary) else { throw HibossAPIError.invalidResponse }
                thumbnails[item.id] = NSImage(cgImage: image, size: .zero)
            }
            files[item.id] = file
            errors[item.id] = nil
            return file
        } catch {
            try? FileManager.default.removeItem(at: directory)
            if current == generation, !Task.isCancelled { errors[item.id] = error.localizedDescription }
            return nil
        }
    }
}
