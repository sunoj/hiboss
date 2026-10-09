// Box content destinations with selectable text, local file preview and reusable zoom viewer.
// Exports BoxTextDetail and BoxMediaDetail; media is obtained through BoxMediaStore.
// Dependencies: SwiftUI, QuickLook, HibossKit and ProgressMediaViewer.

import HibossKit
import QuickLook
import SwiftUI
import UIKit

struct BoxTextDetail: View {
    let item: BoxItem
    @ObservedObject var media: BoxMediaStore
    @State private var previewURL: URL?
    @State private var shareURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BoxProvenanceBadge(item: item)
                if let text = item.text { Text(verbatim: text).textSelection(.enabled) }
                if let note = item.note {
                    Text(verbatim: note).textSelection(.enabled).foregroundStyle(Theme.ink2)
                }
                if item.hasMedia {
                    if let resource = media.resources[item.id] {
                        Button("Open file") { openFile(resource.url) }
                            .buttonStyle(.bordered).frame(minHeight: 44)
                    } else { BoxMediaWait(item: item, media: media) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .navigationTitle(Text(verbatim: item.kindLabel))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("box-text-detail")
        .task {
            await media.load(item)
            if item.kind == .file, let resource = media.resources[item.id] { openFile(resource.url) }
        }
        .quickLookPreview($previewURL)
        .sheet(isPresented: Binding(
            get: { shareURL != nil }, set: { if !$0 { shareURL = nil } }
        )) {
            if let shareURL { BoxFileShareSheet(url: shareURL) }
        }
    }

    private func openFile(_ url: URL) {
        if QLPreviewController.canPreview(url as NSURL) { previewURL = url }
        else { shareURL = url }
    }
}

struct BoxMediaDetail: View {
    let item: BoxItem
    @ObservedObject var media: BoxMediaStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let resource = media.resources[item.id] {
                ProgressMediaViewer(items: [ProgressMedia(
                    url: resource.url.absoluteString, kind: item.kind == .video ? .video : .image,
                    contentType: item.mediaType ?? "application/octet-stream", size: item.mediaBytes ?? 0,
                    width: item.width, height: item.height, durationMs: item.durationMs, alt: item.boxTitle
                )], startIndex: 0, localImages: item.kind == .image ? [
                    resource.url.absoluteString: resource.thumbnail
                ]
                    .compactMapValues { $0 } : [:])
            } else {
                ZStack(alignment: .topLeading) {
                    Theme.mediaBackground.ignoresSafeArea()
                    BoxMediaWait(item: item, media: media).padding().frame(maxHeight: .infinity)
                    Button("Close", systemImage: "xmark.circle.fill") { dismiss() }
                        .font(.title).padding().frame(minHeight: 44)
                }
            }
        }
        .safeAreaInset(edge: .top, alignment: .leading) {
            if !item.author.isBoss {
                BoxProvenanceBadge(item: item)
                    .padding(.horizontal).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial)
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("box-media-detail")
        .task { await media.load(item) }
    }
}

private struct BoxFileShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct BoxMediaWait: View {
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
