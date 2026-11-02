// Session notes list and inline composer with retry-safe submission.
// Exports SessionNotesView, using SessionNotesServing and native Theme styles.
// Dependencies: SwiftUI and HibossKit.

import HibossKit
import SwiftUI

struct SessionNotesView: View {
    let sessionID: String
    let api: any SessionNotesServing
    @State private var notes: [SessionNote] = []
    @State private var canCreate = false
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .trailing, spacing: 16) {
                    if let error {
                        Text(verbatim: error).foregroundStyle(Theme.ink2)
                        Button("Retry") { Task { await load() } }
                    }
                    if !loaded { ProgressView() }
                    if loaded, notes.isEmpty { Text("No notes yet") }
                    ForEach(notes) { note in
                        VStack(alignment: .trailing, spacing: 8) {
                            ForEach(note.images, id: \.index) { image in
                                SessionNotePhoto(note: note, image: image, api: api)
                            }
                            if !note.body.isEmpty { Text(verbatim: note.body).textSelection(.enabled) }
                            HStack(spacing: 4) {
                                timestamp(note.createdAt)
                                Text(verbatim: "·")
                                if note.status == .pending { Text("Unread") }
                                else { Text("Read") }
                                if let readAt = note.readAt { timestamp(readAt) }
                            }.font(.caption).foregroundStyle(Theme.ink2)
                        }
                        .padding(12).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 18))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.leading, 32).id(note.id)
                    }
                    Color.clear.frame(height: 1).id("newest")
                }.padding()
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: notes) { _, _ in proxy.scrollTo("newest", anchor: .bottom) }
        }
        .navigationTitle("Session notes")
        .safeAreaInset(edge: .bottom) {
            if canCreate {
                SessionNoteComposer(sessionID: sessionID, api: api) { note in
                    notes.removeAll { $0.id == note.id }
                    notes.append(note)
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func timestamp(_ value: String) -> some View {
        Group {
            if let date = ISODate.parse(value) { Text(date, format: .dateTime.month().day().hour().minute()) }
            else { Text(verbatim: value) }
        }.font(.caption).foregroundStyle(Theme.ink2)
    }

    private func load() async {
        error = nil
        do {
            notes = try await api.listSessionNotes(sessionID: sessionID)
                .reversed().sorted { $0.createdAt < $1.createdAt }
            loaded = true
            canCreate = try await api.canCreateSessionNotes()
        } catch { self.error = error.localizedDescription }
    }
}
