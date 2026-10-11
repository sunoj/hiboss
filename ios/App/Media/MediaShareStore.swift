// Prepares original media files for the native activity sheet with cancellable reads.
// Exports MediaShareStore and MediaShareSheet; temporary downloads live for the viewer session.
// Dependencies: Foundation, SwiftUI and UIKit.

import SwiftUI
import UIKit

@MainActor
final class MediaShareStore: ObservableObject {
    struct Resource: Identifiable {
        let id = UUID()
        let url: URL
    }

    @Published var resource: Resource?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private var task: Task<Void, Never>?
    private var directory: URL?

    func share(_ item: MediaItem) {
        task?.cancel()
        error = nil
        isLoading = true
        task = Task {
            do {
                let url = try await prepare(item)
                try Task.checkCancellation()
                resource = Resource(url: url)
                isLoading = false
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled {
                    self.error = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        resource = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
    }

    private func prepare(_ item: MediaItem) async throws -> URL {
        if item.url.isFileURL { return item.url }
        let (download, response) = try await URLSession.shared.download(from: item.url)
        defer { try? FileManager.default.removeItem(at: download) }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let folder = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("media-share-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        directory = folder
        let filename = response.suggestedFilename ?? (item.kind == .image ? "image" : "video")
        let destination = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let file = destination.appendingPathComponent(URL(fileURLWithPath: filename).lastPathComponent)
        try FileManager.default.moveItem(at: download, to: file)
        return file
    }
}

struct MediaShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
