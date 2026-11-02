// Authenticated note images retained as temporary resources while the timeline is open.
// Reuses BoxMediaResource lifetime management, RemoteImage and the shared MediaViewer.
import HibossKit
import SwiftUI

struct SessionNotePhoto: View {
    let note: SessionNote
    let image: SessionNoteImage
    let api: any SessionNotesServing
    @State private var resource: BoxMediaResource?
    @State private var error: String?
    @State private var viewing = false

    var body: some View {
        Group {
            if let resource {
                Button { viewing = true } label: {
                    RemoteImage(url: resource.url, compact: true) { image in
                        image.resizable().scaledToFit()
                    }.frame(maxWidth: 260, maxHeight: 180)
                }.buttonStyle(.plain).accessibilityLabel("Open image")
                    .accessibilityIdentifier("session-note-image")
            } else if let error {
                VStack {
                    Text(verbatim: error).font(.caption)
                    Button("Retry image") { Task { await load() } }
                }
            } else { ProgressView().frame(width: 180, height: 100) }
        }
        .task { await load() }
        .fullScreenCover(isPresented: $viewing) {
            if let resource {
                MediaViewer(items: [MediaItem(url: resource.url, kind: .image)], startIndex: 0)
            }
        }
    }

    private func load() async {
        guard resource == nil else { return }
        error = nil
        do {
            let data = try await api.sessionNoteImage(
                sessionID: note.sessionID, noteID: note.id, index: image.index)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            resource = BoxMediaResource(url: url)
        } catch { self.error = error.localizedDescription }
    }
}
