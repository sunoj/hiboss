// Unified Box detail with preview, metadata, note editing and confirmed deletion.
// Exports BoxDetail and BoxMediaWait; file previews return to their owning detail.
// Dependencies: SwiftUI, QuickLook, HibossKit and MediaViewer.

import HibossKit
import QuickLook
import SwiftUI
import UIKit

struct BoxDetail: View {
    let original: BoxItem
    @ObservedObject var store: BoxStore
    @ObservedObject var media: BoxMediaStore
    @State private var previewURL: URL?
    @State private var shareURL: URL?
    @State private var openedMedia: MediaSession?
    @State private var pendingDelete: BoxItem?
    @State private var viewerDelete: BoxItem?
    @State private var editing = false
    @State private var openingError = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var item: BoxItem { store.items.first { $0.id == original.id } ?? original }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                preview
                if item.kind != .text && item.boxTitle != item.url {
                    Text(verbatim: item.boxTitle).font(.title2).textSelection(.enabled)
                }
                if let note = item.note, !note.isEmpty, note != item.boxTitle {
                    Text(verbatim: note).textSelection(.enabled).foregroundStyle(Theme.ink2)
                }
                information
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar { ToolbarItemGroup(placement: .bottomBar) { actions } }
        .alert("Couldn't open link", isPresented: $openingError) {
            Button("OK", role: .cancel) {}
        }
        .accessibilityIdentifier("box-detail")
        .task { await media.load(item) }
        .quickLookPreview($previewURL)
        .fullScreenCover(item: $openedMedia) { session in
            MediaViewer(items: session.items, startIndex: session.index, itemActions: viewerActions)
                .modifier(BoxDeleteConfirmation(item: $viewerDelete, store: store, media: media,
                                                onDeleted: {
                                                    openedMedia = nil
                                                    dismiss()
                                                }))
        }
        .sheet(isPresented: Binding(
            get: { shareURL != nil }, set: { if !$0 { shareURL = nil } }
        )) {
            if let shareURL { BoxShareSheet(items: [shareURL]) }
        }
        .sheet(isPresented: $editing) { BoxNoteEditor(item: item, store: store) }
        .modifier(BoxDeleteConfirmation(item: $pendingDelete, store: store, media: media,
                                        onDeleted: { dismiss() }))
    }

    @ViewBuilder private var preview: some View {
        switch item.kind {
        case .image, .video:
            if let resource = media.resources[item.id] {
                Button {
                    openedMedia = MediaSession(items: [MediaItem(
                        url: resource.url, kind: item.kind == .video ? .video : .image,
                        title: item.boxTitle, caption: item.note)], index: 0)
                } label: {
                    BoxThumbnail(item: item, media: media).frame(height: 220)
                }.buttonStyle(.plain).accessibilityLabel("Open media")
            } else { BoxMediaWait(item: item, media: media) }
        case .text:
            Text(verbatim: item.text ?? "").textSelection(.enabled)
                .padding().frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        case .link:
            Label { Text(verbatim: item.url ?? "").foregroundStyle(Theme.link) } icon: {
                Image(systemName: "globe")
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        case .file:
            BoxThumbnail(item: item, media: media).frame(width: 80, height: 80)
        }
    }

    private var information: some View {
        GroupBox("Information") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Author") { Text(verbatim: item.authorLabel) }
                if let project = item.project, !project.isEmpty {
                    LabeledContent("Project") { Text(verbatim: project) }
                }
                if !item.tags.isEmpty {
                    LabeledContent("Tags") { Text(verbatim: item.tags.formatted(.list(type: .and))) }
                }
                LabeledContent("Format and size") {
                    Text(verbatim: [item.formatLabel, item.sizeLabel]
                        .compactMap { $0 }.joined(separator: " · "))
                }
                if let date = ISOTimestamp.date(from: item.createdAt) {
                    LabeledContent("Added") {
                        Text(date, format: .dateTime.year().month(.wide).day().hour().minute())
                    }
                }
            }.font(.callout)
        }.accessibilityElement(children: .contain)
            .accessibilityIdentifier("box-detail-information")
    }

    private var actions: some View {
        Group {
            Button("Copy", systemImage: "doc.on.doc") { item.copyContent(media: media) }
                .disabled(item.hasMedia && media.resources[item.id] == nil)
            Button("Edit note", systemImage: "square.and.pencil") { editing = true }
            if item.kind == .link {
                Button("Open", systemImage: "arrow.up.right.square") {
                    guard let url = item.url.flatMap(URL.init(string:)),
                          ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
                        openingError = true
                        return
                    }
                    openURL(url) { openingError = !($0) }
                }
            }
            if item.kind == .file {
                Button("Open file", systemImage: "doc") {
                    if let resource = media.resources[item.id] { openFile(resource.url) }
                }.disabled(media.resources[item.id] == nil)
            }
            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = item }
                .disabled(store.deleting.contains(item.id))
            if store.deleting.contains(item.id) {
                PendingStateView(title: String(localized: "Deleting item…"))
            }
        }.labelStyle(.iconOnly)
    }

    private var viewerActions: MediaItemActions {
        MediaItemActions(metadata: { _ in item.authorLabel + " · " + (item.relativeTime ?? "") },
                         copy: { _ in item.copyContent(media: media) },
                         info: { _ in openedMedia = nil }, delete: { _ in viewerDelete = item })
    }

    private func openFile(_ url: URL) {
        if let kind = MediaFileKind.kind(filename: url.lastPathComponent, contentType: item.mediaType) {
            openedMedia = MediaSession(items: [MediaItem(url: url, kind: kind,
                                                       title: item.boxTitle, caption: item.note)], index: 0)
        } else if QLPreviewController.canPreview(url as NSURL) { previewURL = url }
        else { shareURL = url }
    }
}

struct BoxMediaWait: View {
    let item: BoxItem
    @ObservedObject var media: BoxMediaStore

    var body: some View {
        if let error = media.errors[item.id] {
            ContentUnavailableView {
                Label("Media unavailable", systemImage: "photo.badge.exclamationmark")
            } description: { Text(verbatim: error) } actions: {
                RetryButton { await media.retry(item) }
            }
        } else {
            PendingStateView(
                title: String(localized: "Loading Box media…"), onRetry: { await media.retry(item) }
            )
        }
    }
}
