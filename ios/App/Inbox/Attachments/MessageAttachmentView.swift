// Inline agent attachments with image retry/zoom and system links for other files.
// Exports: MessageAttachmentView for full-body message surfaces.
// Dependencies: HibossKit, SwiftUI, RemoteImage, ProgressMediaViewer and demo image fixtures.

import HibossKit
import SwiftUI

struct MessageAttachmentView: View {
    let attachment: MessageAttachment
    @State private var viewingImage = false

    var body: some View {
        switch attachment.kind {
        case .image:
            thumbnail
                .fullScreenCover(isPresented: $viewingImage) {
                    ProgressMediaViewer(items: [ProgressMedia(
                        url: imageResource, kind: .image, contentType: "image/*", size: 0,
                        alt: attachment.filename
                    )], startIndex: 0)
                }
        case .file:
            Link(
                destination: attachment.url
            ) {
                Label { Text(verbatim: attachment.filename) } icon: {
                    Image(systemName: "doc")
                }
                .font(.hbCallout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("message-attachment-file")
        }
    }

    private var imageResource: String {
        DemoMessageAttachments.imageResource(for: attachment.url)
    }

    private var thumbnail: some View {
        Rectangle().fill(Theme.surface2)
            .aspectRatio(1.5, contentMode: .fit)
            .overlay {
                Button { viewingImage = true } label: {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open image for \(attachment.filename)")
                .accessibilityIdentifier("message-attachment-open")
            }
            .overlay {
                RemoteImage(url: URL(string: imageResource), compact: true,
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
