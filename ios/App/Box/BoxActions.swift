// Shared confirmed deletion, native sharing and note editing for every Box destination.
// Exports Box actions, native sharing, note editing and inline file previews.
// Dependencies: SwiftUI, UIKit, PDFKit, HibossKit and the Box stores.

import HibossKit
import PDFKit
import SwiftUI
import UIKit

protocol BoxNoteServing: BoxServing {
    func patchBoxItem(id: String, patch: BoxPatch) async throws -> BoxItem
}

extension HibossAPI: BoxNoteServing {}

struct BoxDeleteConfirmation: ViewModifier {
    @Binding var item: BoxItem?
    @ObservedObject var store: BoxStore
    @ObservedObject var media: BoxMediaStore
    var onDeleted: () -> Void = {}
    @State private var showsDeleteError = false
    @Environment(\.openConnectionSettings) private var openSettings

    func body(content: Content) -> some View {
        content
            .alert(Text(verbatim: alertTitle), isPresented: Binding(
                get: { item != nil || showsDeleteError }, set: { presented in
                    if !presented {
                        item = nil
                        showsDeleteError = false
                    }
                }
            )) {
                if showsDeleteError {
                    Button("OK", role: .cancel) {}
                    Button("Settings", action: openSettings)
                } else if let target = item {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) { Task { await delete(target) } }
                }
            } message: {
                if showsDeleteError { Text(verbatim: store.deleteError ?? "") }
                else { Text("Agents will no longer be able to read this item.") }
            }
    }

    private var alertTitle: String {
        showsDeleteError ? String(localized: "Couldn't delete item")
            : String(localized: "Delete \(item?.boxTitle ?? "")?")
    }

    private func delete(_ target: BoxItem) async {
        await store.delete(target)
        if !store.items.contains(where: { $0.id == target.id }) {
            media.remove(id: target.id)
            onDeleted()
        } else if store.deleteError != nil { showsDeleteError = true }
    }
}

struct BoxShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct BoxShareDestination: View {
    let item: BoxItem
    @ObservedObject var media: BoxMediaStore

    var body: some View {
        Group {
            if !item.hasMedia || media.resources[item.id] != nil {
                BoxShareSheet(items: item.shareContent(media: media))
            } else { BoxMediaWait(item: item, media: media).padding() }
        }.task { await media.load(item) }
    }
}

struct BoxNoteEditor: View {
    let item: BoxItem
    @ObservedObject var store: BoxStore
    @Environment(\.dismiss) private var dismiss
    @State private var note: String

    init(item: BoxItem, store: BoxStore) {
        self.item = item
        self.store = store
        _note = State(initialValue: item.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    TextEditor(text: $note).frame(minHeight: 160)
                        .accessibilityIdentifier("box-note-draft")
                        .disabled(store.isSavingNote)
                }
                if store.isSavingNote {
                    PendingStateView(title: String(localized: "Saving note…"))
                }
                if let error = store.noteError { Text(verbatim: error).foregroundStyle(Theme.negative) }
            }
            .navigationTitle("Edit note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(store.isSavingNote)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { if await store.saveNote(note, for: item) { dismiss() } }
                    }.disabled(store.isSavingNote)
                }
            }
        }
    }
}

extension BoxItem {
    @MainActor func copyContent(media: BoxMediaStore) {
        if kind == .image, let image = media.resources[id]?.thumbnail {
            UIPasteboard.general.image = image
        } else if let url = media.resources[id]?.url {
            UIPasteboard.general.url = url
        } else { UIPasteboard.general.string = self.url ?? text ?? note ?? "" }
    }

    @MainActor func shareContent(media: BoxMediaStore) -> [Any] {
        if [.image, .video, .file].contains(kind) {
            return media.resources[id].map { [$0.url] } ?? []
        }
        if let url = url.flatMap(URL.init(string:)) { return [url] }
        return [text ?? note ?? boxTitle]
    }
}

struct BoxFilePreview: View {
    let item: BoxItem
    @ObservedObject var media: BoxMediaStore
    let open: (URL) -> Void
    @State private var page: UIImage?
    @Binding var unreadable: Bool
    @State private var locked = false

    var body: some View {
        Group {
            if let resource = media.resources[item.id] {
                Button { open(resource.url) } label: {
                    VStack(spacing: 8) {
                        if let page {
                            Image(uiImage: page).resizable().scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 420)
                                .border(Theme.ink2.opacity(0.2))
                        } else if locked {
                            Label("Locked PDF", systemImage: "lock.doc")
                        } else if unreadable {
                            Label("PDF preview unavailable", systemImage: "doc")
                        } else if isPDF(resource.url) {
                            ProgressView()
                        } else {
                            BoxThumbnail(item: item, media: media).frame(width: 80, height: 80)
                        }
                        Label("Open file", systemImage: "arrow.up.right.square")
                            .font(.callout).foregroundStyle(Theme.link)
                    }
                }
                .buttonStyle(.plain).accessibilityLabel("Open file")
                .accessibilityIdentifier("box-file-preview")
                .accessibilityValue(Text(verbatim: locked ? "Locked PDF"
                    : unreadable ? "PDF preview unavailable" : page == nil ? "" : "PDF"))
            } else { BoxMediaWait(item: item, media: media) }
        }
        .task(id: media.resources[item.id]?.url) {
            page = nil
            unreadable = false
            locked = false
            guard let url = media.resources[item.id]?.url, isPDF(url) else { return }
            let worker = Task.detached(priority: .userInitiated) { BoxPDFPreview.load(url) }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            page = result.page
            locked = result.locked
            unreadable = result.unreadable
        }
    }

    private func isPDF(_ url: URL) -> Bool {
        item.mediaType == "application/pdf" || url.pathExtension.lowercased() == "pdf"
    }
}

struct BoxPDFPreview: @unchecked Sendable {
    let page: UIImage?
    let locked: Bool
    let unreadable: Bool

    nonisolated static func load(_ url: URL) -> BoxPDFPreview {
        guard !Task.isCancelled, let document = PDFDocument(url: url) else {
            return BoxPDFPreview(page: nil, locked: false, unreadable: true)
        }
        if document.isEncrypted && document.isLocked {
            return BoxPDFPreview(page: nil, locked: true, unreadable: false)
        }
        guard !Task.isCancelled, let first = document.page(at: 0) else {
            return BoxPDFPreview(page: nil, locked: false, unreadable: true)
        }
        let page = first.thumbnail(of: CGSize(width: 700, height: 900), for: .cropBox)
        return BoxPDFPreview(page: page, locked: false, unreadable: false)
    }
}
