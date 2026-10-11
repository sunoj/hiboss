// Native iPhone reading sheet for Markdown attachments with retry and original-file access.
// Exports MarkdownAttachmentPreview; downloaded document content remains selectable.
// Dependencies: SwiftUI and the shared bounded Markdown document reader.

import HibossKit
import SwiftUI

struct MarkdownAttachmentPreview: View {
    let url: URL
    let filename: String
    @Environment(\.dismiss) private var dismiss
    @State private var source: String?
    @State private var error: String?
    @State private var attempt = 0

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text(verbatim: filename))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Link("Open original", destination: url)
                    }
                }
                .task(id: attempt) { await load() }
        }
        .accessibilityIdentifier("message-attachment-markdown-document")
    }

    @ViewBuilder private var content: some View {
        if let source {
            ScrollView {
                MarkdownDocumentView(source: source).padding(16)
            }
        } else if let error {
            ContentUnavailableView {
                Label("Document unavailable", systemImage: "doc.badge.ellipsis")
            } description: {
                Text(verbatim: error)
            } actions: {
                Button("Retry") { attempt += 1 }
            }
        } else {
            ProgressView("Loading document…").frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func load() async {
        source = nil
        error = nil
        do {
            let document: String
            if let fixture = DemoMessageAttachments.markdownSource(for: url) {
                document = fixture
            } else {
                document = try await MarkdownAttachmentDocument.read(url)
            }
            try Task.checkCancellation()
            source = document
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}
