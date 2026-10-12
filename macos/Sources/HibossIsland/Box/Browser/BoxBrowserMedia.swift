// Authenticated Box downloads stored in isolated temporary directories for native opening.
// Exports: BoxBrowserMedia with deduplicated downloads and image thumbnails.
// Dependencies: AppKit, ImageIO, UniformTypeIdentifiers and BoxBrowserStore.Provider.

import AppKit
import AVFoundation
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

    private var authorizationObservation: AnyCancellable?

    init(apiProvider: @escaping BoxBrowserStore.Provider) {
        self.apiProvider = apiProvider
        authorizationObservation = AccountAuthorization.shared.observe { [weak self] _ in
            self?.reset()
        }
    }

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
            if item.hasImageMedia || item.kind == .video {
                // Decoding a full-size image takes tens of milliseconds; keep it off the main actor.
                let image = await Task.detached(priority: .userInitiated, operation: {
                    await Self.previewThumbnail(of: file, kind: item.kind)
                }).value
                try Task.checkCancellation()
                guard current == generation else { throw CancellationError() }
                if let image { thumbnails[item.id] = NSImage(cgImage: image, size: .zero) }
                else if item.kind != .video { throw HibossAPIError.invalidResponse }
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

    nonisolated private static func previewThumbnail(of file: URL, kind: BoxItem.Kind) async -> CGImage? {
        if kind == .video {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 800, height: 800)
            return try? await generator.image(at: .zero).image
        }
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1000,
            kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary)
    }
}
