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
                .task { await load() }
        }
        .accessibilityIdentifier("message-attachment-markdown-document")
    }

    @ViewBuilder private var content: some View {
        if let source {
            ScrollView {
                MediaMarkdownView(source, document: true, baseURL: url).padding(16)
            }
        } else if let error {
            ContentUnavailableView {
                Label("Document unavailable", systemImage: "doc.badge.ellipsis")
            } description: {
                Text(verbatim: error)
            } actions: {
                RetryButton(action: load)
            }
        } else {
            ProgressView("Loading document…").frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func load() async {
        guard source == nil else { return }
        do {
            let document: String
            if let fixture = try await DemoMessageAttachments.previewSource(for: url) {
                document = fixture
            } else {
                document = try await MarkdownAttachmentDocument.read(url)
            }
            try Task.checkCancellation()
            source = document
            error = nil
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}
