// Native in-app reading surface for a public Markdown file attachment.
// Exports: MarkdownAttachmentPreview with loading, retry, close, and original-file actions.
// Dependencies: SwiftUI, MarkdownAttachmentDocument, and MarkdownDocumentView.

import SwiftUI
import HibossKit

struct MarkdownAttachmentPreview: View {
    let url: URL
    let filename: String
    @Environment(\.dismiss) private var dismiss
    @State private var source: String?
    @State private var error: String?
    @State private var attempt = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(filename, systemImage: "doc.text").font(.headline).textSelection(.enabled)
                Spacer()
                Link(L("Open original"), destination: url)
                Button(L("Close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding()
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 480, idealWidth: 760, maxWidth: 900,
            minHeight: 360, idealHeight: 640, maxHeight: 800)
        .task(id: attempt) { await load() }
        .accessibilityIdentifier("message.attachment.markdown.document")
    }

    @ViewBuilder private var content: some View {
        if let source {
            ScrollView {
                MarkdownDocumentView(source: source).padding(24)
            }
        } else if let error {
            VStack(spacing: 12) {
                Label(L("Document unavailable"), systemImage: "doc.badge.ellipsis").font(.headline)
                Text(error).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(L("Retry")) { attempt += 1 }
            }.padding()
        } else {
            ProgressView(L("Loading document…"))
        }
    }

    private func load() async {
        source = nil
        error = nil
        do {
            let document = try await MarkdownAttachmentDocument.read(url)
            try Task.checkCancellation()
            source = document
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}
