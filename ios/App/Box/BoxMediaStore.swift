// Authenticated media downloads and local image/video thumbnails for Box rows and viewers.
// Exports BoxMediaStore and BoxMediaResource; temporary bytes are removed with their resource.
// Dependencies: HibossKit, AVFoundation, UIKit and UniformTypeIdentifiers.

import AVFoundation
import Combine
import HibossKit
import UIKit
import UniformTypeIdentifiers

final class BoxMediaResource {
    let url: URL
    let thumbnail: UIImage?

    init(url: URL, thumbnail: UIImage?) {
        self.url = url
        self.thumbnail = thumbnail
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}

@MainActor
final class BoxMediaStore: ObservableObject {
    @Published private(set) var resources: [String: BoxMediaResource] = [:]
    @Published private(set) var errors: [String: String] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    private let api: (any BoxServing)?

    init(api: (any BoxServing)?) { self.api = api }

    func load(_ item: BoxItem) async {
        guard item.hasMedia, resources[item.id] == nil else { return }
        if let task = tasks[item.id] { await task.value; return }
        let task = Task { await download(item) }
        tasks[item.id] = task
        await task.value
        tasks[item.id] = nil
    }

    func retry(_ item: BoxItem) async {
        tasks[item.id]?.cancel()
        await tasks[item.id]?.value
        tasks[item.id] = nil
        errors[item.id] = nil
        await load(item)
    }

    func remove(id: String) {
        tasks[id]?.cancel()
        resources[id] = nil
        errors[id] = nil
    }

    private func download(_ item: BoxItem) async {
        guard let api else { return }
        let ext = item.mediaType.flatMap { UTType(mimeType: $0)?.preferredFilenameExtension } ?? "bin"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("box-\(UUID().uuidString)").appendingPathExtension(ext)
        do {
            try await api.downloadBoxMedia(id: item.id, to: url)
            let thumbnail = try await thumbnail(item, url: url)
            try Task.checkCancellation()
            resources[item.id] = BoxMediaResource(url: url, thumbnail: thumbnail)
            errors[item.id] = nil
        } catch {
            try? FileManager.default.removeItem(at: url)
            guard !Task.isCancelled else { return }
            errors[item.id] = error.localizedDescription
        }
    }

    private func thumbnail(_ item: BoxItem, url: URL) async throws -> UIImage? {
        if item.kind == .image {
            guard let image = UIImage(contentsOfFile: url.path) else { throw HibossAPIError.invalidResponse }
            return image
        }
        guard item.kind == .video else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 512, height: 512)
        let frame = try await generator.image(at: .zero)
        return UIImage(cgImage: frame.image)
    }
}
