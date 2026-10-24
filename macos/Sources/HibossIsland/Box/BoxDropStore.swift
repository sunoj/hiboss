// Owns a drop draft, upload state and stable per-item retry identities.
// Exports BoxDropStore; successful items are skipped after a partial failure, and image and
// video uploads carry the shared JPEG thumbnail part when one can be made.
// Dependencies: Combine, UniformTypeIdentifiers, the HibossKit Box create contract and generator.

import Combine
import Foundation
import HibossKit
import UniformTypeIdentifiers

@MainActor
final class BoxDropStore: ObservableObject {
    enum Phase: Equatable { case loading, ready, uploading, failed, rejected, saved }
    typealias Sender = @MainActor (BoxUpload, String) async throws -> Void

    @Published private(set) var phase: Phase = .loading
    @Published var note = ""
    @Published private(set) var error: String?
    @Published private(set) var payloads: [BoxDropPayload] = []
    @Published private(set) var completed = 0
    private(set) var keys: [String] = []
    private var savedNote: String?
    private let send: Sender

    init(send: @escaping Sender) { self.send = send }

    func prepare(_ inputs: [BoxDropInput]) async {
        do {
            let payloads = try await Task.detached {
                try BoxDropPayload.load(inputs)
            }.value
            self.payloads = payloads
            keys = payloads.map { _ in UUID().uuidString }
            phase = .ready
        } catch {
            reject(error)
        }
    }

    func reject(_ error: Error) {
        self.error = (error as? BoxDropError)?.localizedDescription
            ?? BoxDropError.unreadable.localizedDescription
        phase = .rejected
    }

    var noteLocked: Bool { savedNote != nil || phase != .ready }

    private func upload(_ payload: BoxDropPayload, key: String) async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let ext = payload.upload.flatMap { UTType(mimeType: $0.mediaType)?.preferredFilenameExtension }
        // AVFoundation needs the extension to read a video poster frame.
        let fileURL = ext.map { base.appendingPathExtension($0) } ?? base
        let thumbnailURL = base.appendingPathExtension("thumbnail.jpg")
        defer {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: thumbnailURL)
        }
        var media: BoxUpload.Media?
        var thumbnail: BoxUpload.Media?
        if let snapshot = payload.upload {
            try snapshot.data.write(to: fileURL, options: .atomic)
            media = BoxUpload.Media(fileURL: fileURL, contentType: snapshot.mediaType)
            if await Self.writeThumbnail(of: fileURL, kind: payload.kind, to: thumbnailURL) {
                thumbnail = BoxUpload.Media(fileURL: thumbnailURL, contentType: BoxThumbnailGenerator.contentType)
            }
        }
        try await send(BoxUpload(text: payload.text, url: payload.url,
            note: savedNote?.isEmpty == false ? savedNote : nil, source: .macDrop, media: media,
            thumbnail: thumbnail), key)
    }

    /// The shared JPEG thumbnail for an image or video; a drop uploads without one when it fails.
    private static func writeThumbnail(of file: URL, kind: BoxItem.Kind, to url: URL) async -> Bool {
        guard kind == .image || kind == .video else { return false }
        return await Task.detached(priority: .userInitiated) {
            guard let data = await BoxThumbnailGenerator.thumbnail(for: file, kind: kind) else { return false }
            return (try? data.write(to: url, options: .atomic)) != nil
        }.value
    }

    func save() async {
        guard phase == .ready || phase == .failed else { return }
        guard note.utf8.count <= 16 * 1024 else {
            error = BoxDropError.noteLimit.localizedDescription
            return
        }
        if savedNote == nil { savedNote = note }
        error = nil
        phase = .uploading
        do {
            while completed < payloads.count {
                let payload = payloads[completed]
                try await upload(payload, key: keys[completed])
                completed += 1
            }
            phase = .saved
        } catch {
            self.error = L("Couldn't save to Box. Check your connection and retry.")
            phase = .failed
        }
    }
}
