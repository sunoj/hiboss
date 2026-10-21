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
    fileprivate(set) var thumbnail: UIImage?
    private let directory: URL?

    init(url: URL, thumbnail: UIImage?, directory: URL? = nil) {
        self.url = url
        self.thumbnail = thumbnail
        self.directory = directory
    }

    deinit { try? FileManager.default.removeItem(at: directory ?? url) }
}

@MainActor
final class BoxMediaStore: ObservableObject {
    @Published private(set) var resources: [String: BoxMediaResource] = [:]
    @Published private(set) var errors: [String: String] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    private let api: (any BoxServing)?

    init(api: (any BoxServing)?) { self.api = api }

    func load(_ item: BoxItem) async {
        guard item.hasMedia, resources[item.id] == nil, errors[item.id] == nil else { return }
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

    func loadSelection(id: String, items: [BoxItem]) async {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        for position in [index, index + 1, index - 1] where items.indices.contains(position) {
            guard !Task.isCancelled else { return }
            await load(items[position])
        }
    }

    func remove(id: String) {
        tasks[id]?.cancel()
        resources[id] = nil
        errors[id] = nil
    }

    private func download(_ item: BoxItem) async {
        guard let api else { return }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("box-\(UUID().uuidString)")
        let pending = directory.appendingPathComponent("download")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try await api.downloadBoxMedia(id: item.id, to: pending)
            let url = directory.appendingPathComponent(try BoxDownloadName.filename(item, bytesAt: pending))
            if url != pending { try FileManager.default.moveItem(at: pending, to: url) }
            let image = item.kind == .video ? nil : try await thumbnail(item, url: url)
            try Task.checkCancellation()
            let resource = BoxMediaResource(url: url, thumbnail: image, directory: directory)
            resources[item.id] = resource
            errors[item.id] = nil
            if item.kind == .video {
                let poster = try? await thumbnail(item, url: url)
                guard !Task.isCancelled, resources[item.id] === resource else { return }
                objectWillChange.send()
                resource.thumbnail = poster
            }
        } catch {
            try? FileManager.default.removeItem(at: directory)
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

private enum BoxDownloadName {
    static func filename(_ item: BoxItem, bytesAt url: URL) throws -> String {
        let raw = item.text.flatMap { $0.isEmpty ? nil : $0 } ?? item.boxTitle
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))
        let safe = raw.unicodeScalars.map { forbidden.contains($0) ? "-" : String($0) }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        let ownExtension = realExtension((safe as NSString).pathExtension)
        let mimeExtension = item.mediaType.flatMap { UTType(mimeType: $0)?.preferredFilenameExtension }
        let typedExtension = mimeExtension.flatMap { $0 == "bin" ? nil : $0 }
        let ext = try typedExtension ?? (ownExtension.isEmpty ? nil : bounded(ownExtension, bytes: 32))
            ?? sniff(url) ?? "bin"
        let stem = ownExtension.isEmpty ? safe : (safe as NSString).deletingPathExtension
        let name = bounded(stem, bytes: 200)
        return "\(name.isEmpty ? "attachment" : name).\(ext)"
    }

    /// A trailing ".12" or ".2 notes" is part of the title, not a file extension.
    private static func realExtension(_ candidate: String) -> String {
        guard !candidate.isEmpty, candidate.utf8.count <= 32,
              candidate.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.alphanumerics.contains($0) })
        else { return "" }
        let lettersOnly = candidate.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) }
        return lettersOnly || UTType(filenameExtension: candidate)?.isDeclared == true ? candidate : ""
    }

    private static func bounded(_ value: String, bytes: Int) -> String {
        var result = ""
        for character in value {
            guard result.utf8.count + String(character).utf8.count <= bytes else { break }
            result.append(character)
        }
        return result
    }

    private static func sniff(_ url: URL) throws -> String? {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let bytes = Array(try file.read(upToCount: 16) ?? Data())
        if bytes.starts(with: Array("%PDF-".utf8)) { return "pdf" }
        if bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) { return "png" }
        if bytes.starts(with: [255, 216, 255]) { return "jpg" }
        if bytes.starts(with: Array("GIF87a".utf8)) || bytes.starts(with: Array("GIF89a".utf8)) {
            return "gif"
        }
        if [[80, 75, 3, 4], [80, 75, 5, 6], [80, 75, 7, 8]].contains(where: { bytes.starts(with: $0) }) {
            return "zip"
        }
        if bytes.count >= 12, String(bytes: bytes[4..<8], encoding: .ascii) == "ftyp" {
            return String(bytes: bytes[8..<12], encoding: .ascii) == "qt  " ? "mov" : "mp4"
        }
        return nil
    }
}
