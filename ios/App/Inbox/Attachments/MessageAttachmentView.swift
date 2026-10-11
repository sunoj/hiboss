// Inline agent attachments with image retry/zoom and system links for other files.
// Exports: MessageAttachmentView for full-body message surfaces.
// Dependencies: HibossKit, SwiftUI, RemoteImage, MediaViewer and demo image fixtures.

import HibossKit
import SwiftUI

struct MessageAttachmentView: View {
    let attachment: MessageAttachment
    @State private var viewingMedia = false
    @State private var viewingMarkdown = false
    @State private var documentInfo: MarkdownAttachmentInfo?

    private var info: MarkdownAttachmentInfo {
        documentInfo ?? MarkdownAttachmentInfo(url: attachment.url)
    }

    var body: some View {
        Group {
            if mediaKind == .image { thumbnail }
            else if mediaKind == .video { videoButton }
            else { document }
        }
        .fullScreenCover(isPresented: $viewingMedia) {
            if let url = URL(string: mediaResource), let mediaKind {
                MediaViewer(items: [MediaItem(url: url, kind: mediaKind,
                                             title: info.filename)], startIndex: 0)
            }
        }
        .task(id: attachment.url) {
            documentInfo = nil
            if attachment.url.pathExtension.isEmpty {
                let resolved = try? await MarkdownAttachmentDocument.inspect(attachment.url)
                if !Task.isCancelled { documentInfo = resolved }
            }
        }
    }

    private var mediaKind: MediaItem.Kind? {
        attachment.kind == .image ? .image : MediaFileKind.kind(filename: info.filename)
    }

    private var videoButton: some View {
        Button { viewingMedia = true } label: {
            Label { Text(verbatim: info.filename) } icon: { Image(systemName: "play.rectangle") }
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("message-attachment-video-open")
    }

    private var document: some View {
        VStack(alignment: .leading, spacing: 8) {
            Link(destination: attachment.url) {
                Label { Text(verbatim: info.filename) } icon: { Image(systemName: "doc") }
                    .font(.hbCallout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("message-attachment-file")
            if info.isMarkdown {
                Button { viewingMarkdown = true } label: {
                    Label("Preview Markdown", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("message-attachment-markdown-preview")
            }
        }
        .sheet(isPresented: $viewingMarkdown) {
            MarkdownAttachmentPreview(url: attachment.url, filename: info.filename)
        }
    }

    private var mediaResource: String {
        DemoMessageAttachments.mediaResource(for: attachment.url)
    }

    private var thumbnail: some View {
        Rectangle().fill(Theme.surface2)
            .aspectRatio(1.5, contentMode: .fit)
            .overlay {
                Button { viewingMedia = true } label: {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open image for \(attachment.filename)")
                .accessibilityIdentifier("message-attachment-open")
            }
            .overlay {
                RemoteImage(url: URL(string: mediaResource), compact: true,
                            retryIdentifier: "message-attachment-retry") { image in
                    image.resizable().scaledToFit()
                        .allowsHitTesting(false)
                        .accessibilityLabel(Text(verbatim: attachment.filename))
                        .accessibilityIdentifier("message-attachment-image")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
