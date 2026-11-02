// Inline note drafts with photo selection and retry-safe submission.
// Uses PhotosUI, HibossKit and image preparation before uploading.
import HibossKit
import PhotosUI
import SwiftUI

struct SessionNoteComposer: View {
    let sessionID: String
    let api: any SessionNotesServing
    let onSent: (SessionNote) -> Void
    @State private var bodyText = ""
    @State private var sending = false
    @State private var error: String?
    @State private var attempt: (body: String, images: [SessionNoteUpload], key: String)?
    @State private var selection: [PhotosPickerItem] = []
    @State private var images: [SessionNoteUpload] = []
    @State private var loading = false
    private var trimmed: String { bodyText.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            thumbnails
            if let error { Text(verbatim: error).font(.caption).foregroundStyle(Theme.ink2) }
            HStack(alignment: .bottom) {
                PhotosPicker(selection: $selection,
                             maxSelectionCount: max(1, 4 - images.count), matching: .images) {
                    Image(systemName: "photo").frame(width: 44, height: 44)
                }.accessibilityLabel("Add images").disabled(sending || loading || images.count == 4)
                draftField
                Button(action: send) {
                    if sending { ProgressView().frame(width: 44, height: 44) }
                    else {
                        Image(systemName: "arrow.up.circle.fill").font(.title).frame(width: 44, height: 44)
                    }
                }.accessibilityLabel("Send note")
                    .disabled(sending || loading || (trimmed.isEmpty && images.isEmpty))
                    .accessibilityIdentifier("send-session-note")
            }
            Text(verbatim: "\(bodyText.unicodeScalars.count) / 4000")
                .font(.caption2).foregroundStyle(Theme.ink2)
        }.padding().background(.bar)
            .onChange(of: selection) { _, items in
                if !items.isEmpty { Task { await loadImages(items) } }
            }
    }

    @ViewBuilder
    private var thumbnails: some View {
        if !images.isEmpty {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(images.indices, id: \.self) { index in
                        if let image = UIImage(data: images[index].data) {
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 64, height: 64)
                                .clipped().overlay(alignment: .topTrailing) {
                                    Button { images.remove(at: index) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .frame(width: 44, height: 44)
                                    }.accessibilityLabel("Remove image").disabled(sending || loading)
                                }
                        }
                    }
                }
            }.accessibilityIdentifier("session-note-thumbnails")
        }
    }

    private var draftField: some View {
        TextField("", text: $bodyText,
                  prompt: Text("Write a note…").foregroundStyle(Theme.ink2), axis: .vertical)
            .lineLimit(1...5).textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("session-note-body").disabled(sending)
            .onChange(of: bodyText) { _, value in
                if value.unicodeScalars.count > 4000 {
                    bodyText = String(String.UnicodeScalarView(value.unicodeScalars.prefix(4000)))
                }
            }
    }

    private func loadImages(_ items: [PhotosPickerItem]) async {
        loading = true
        defer {
            loading = false
            selection = []
        }
        do {
            for item in items where images.count < 4 {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                images.append(try SessionNoteImagePreparation.prepare(data))
            }
        } catch { self.error = error.localizedDescription }
    }

    private func send() {
        guard !sending, (!trimmed.isEmpty || !images.isEmpty),
              trimmed.unicodeScalars.count <= 4000 else { return }
        if attempt?.body != trimmed || attempt?.images != images {
            attempt = (trimmed, images, UUID().uuidString)
        }
        guard let attempt else { return }
        sending = true
        error = nil
        Task {
            defer { sending = false }
            do {
                let note = try await api.createSessionNote(
                    sessionID: sessionID, body: attempt.body, images: attempt.images,
                    idempotencyKey: attempt.key)
                onSent(note)
                bodyText = ""
                images = []
                self.attempt = nil
            } catch { self.error = error.localizedDescription }
        }
    }
}
