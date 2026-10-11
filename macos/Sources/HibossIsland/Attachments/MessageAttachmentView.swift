// Inline attachment preview and native links to public message files.
// Exports: MessageAttachmentView, with a bounded thumbnail and a persistent filename link.
// Dependencies: SwiftUI, HibossKit MessageAttachment, and public Markdown attachment metadata.

import HibossKit
import SwiftUI

struct MessageAttachmentView: View {
    let attachment: MessageAttachment
    @State private var documentInfo: MarkdownAttachmentInfo?
    @State private var previewPresented = false

    private var info: MarkdownAttachmentInfo {
        documentInfo ?? MarkdownAttachmentInfo(url: attachment.url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if attachment.kind == .image {
                Link(destination: attachment.url) {
                    AsyncImage(url: attachment.url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        case .failure:
                            Label(L("Image unavailable"), systemImage: "photo.badge.exclamationmark")
                                .foregroundStyle(.secondary)
                        case .empty:
                            ProgressView()
                        @unknown default:
                            Image(systemName: "photo").foregroundStyle(.secondary)
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .frame(maxWidth: 280)
                    .frame(height: 180)
                    .background(Color(nsColor: .controlBackgroundColor))
                }
                .accessibilityLabel(L("Open image for \(attachment.filename)"))
                .accessibilityIdentifier("message.attachment.image")
            }
            Link(destination: attachment.url) {
                Label(info.filename, systemImage: "paperclip")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("message.attachment.file")
            if info.isMarkdown {
                Button(L("Preview Markdown"), systemImage: "doc.text.magnifyingglass") {
                    previewPresented = true
                }
                .accessibilityIdentifier("message.attachment.markdown.preview")
            }
        }
        .task(id: attachment.url) {
            documentInfo = nil
            if attachment.kind == .file && attachment.url.pathExtension.isEmpty {
                documentInfo = try? await MarkdownAttachmentDocument.inspect(attachment.url)
            }
        }
        .sheet(isPresented: $previewPresented) {
            MarkdownAttachmentPreview(url: attachment.url, filename: info.filename)
        }
    }
}
