// Retains drafts, prepared attachments and idempotency keys across upload retries.
// Exports ShareViewModel and its named loading, compression, upload and completion states.
// Dependencies: Combine, HibossKit and the share attachment/media helpers.

import Combine
import HibossKit
import UIKit

@MainActor
final class ShareViewModel: ObservableObject {
    enum State: Equatable { case loading, ready, compressing, uploading, done, failure, disconnected }
    @Published private(set) var state: State = .loading
    @Published private(set) var attachments: [ShareAttachment] = []
    @Published private(set) var projects: [ProgressProject] = []
    @Published private(set) var projectFailure = false
    @Published private(set) var progress = 0.0
    @Published private(set) var failure = ""
    @Published var note = ""
    @Published var project = ""

    private let api: (any BoxUploading)?
    private let prepare: @Sendable (BoxUpload.Media, BoxItem.Kind) async throws -> BoxUpload.Media
    private var prepared: [UUID: BoxUpload.Media] = [:]
    private var completed: Set<UUID> = []
    private var pending: [UUID: BoxUpload] = [:]

    init(
        api: (any BoxUploading)?, attachments: [ShareAttachment] = [],
        prepare: @escaping @Sendable (BoxUpload.Media, BoxItem.Kind) async throws -> BoxUpload.Media = {
            try await ShareMediaPreparer.prepare($0, kind: $1)
        }
    ) {
        self.api = api
        self.attachments = attachments
        self.prepare = prepare
        if api == nil { state = .disconnected }
        else if !attachments.isEmpty { state = .ready }
    }

    var isBusy: Bool { [.loading, .compressing, .uploading].contains(state) }

    func load(_ providers: [NSItemProvider], directory: URL) async {
        guard api != nil else { return }
        state = .loading
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            attachments = try await ShareAttachmentLoader.load(providers, directory: directory)
            state = .ready
        } catch { fail(error) }
    }

    func loadProjects(using api: any ProgressServing) async {
        do {
            let rows = try await api.progressProjects()
            projects = Dictionary(grouping: rows, by: \.slug).compactMap { $0.value.first }
                .sorted { $0.slug.localizedStandardCompare($1.slug) == .orderedAscending }
            projectFailure = false
        } catch { projectFailure = true }
    }

    func save() async {
        guard let api, !isBusy, state != .done, !attachments.isEmpty else { return }
        guard note.utf8.count <= SharePolicy.textBytes else { return fail(ShareError.textTooLarge) }
        progress = Double(completed.count) / Double(attachments.count)
        do {
            for item in attachments where !completed.contains(item.id) {
                try Task.checkCancellation()
                let upload = try await payload(for: item)
                try Task.checkCancellation()
                state = .uploading
                let base = completed.count
                let count = attachments.count
                _ = try await api.createBoxItem(upload, idempotencyKey: item.idempotencyKey) {
                    [weak self] value in
                    Task { @MainActor in
                        guard self?.state == .uploading else { return }
                        self?.progress = max(self?.progress ?? 0, (Double(base) + value) / Double(count))
                    }
                }
                completed.insert(item.id)
                progress = Double(completed.count) / Double(attachments.count)
            }
            state = .done
        } catch { fail(error) }
    }

    private func payload(for item: ShareAttachment) async throws -> BoxUpload {
        if let pending = pending[item.id] { return pending }
        var media = prepared[item.id]
        if media == nil, let original = item.media {
            state = .compressing
            media = try await prepare(original, item.kind)
            prepared[item.id] = media
        }
        if let value = item.url ?? item.text,
           SharePolicy.decision(kind: item.kind, bytes: value.utf8.count) == .refuse {
            throw ShareError.textTooLarge
        }
        let upload = BoxUpload(text: item.text, url: item.url, note: note.isEmpty ? nil : note,
            project: project.isEmpty ? nil : project, source: .iosShare, media: media)
        pending[item.id] = upload
        return upload
    }

    private func fail(_ error: Error) {
        failure = (error as? ShareError)?.localizedDescription
            ?? String(localized: "Could not save to Box. Check your connection and retry.")
        state = .failure
    }
}
