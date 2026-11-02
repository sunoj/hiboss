// Session notes list and independent compose sheet with retry-safe submission.
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
    @State private var composing = false

    var body: some View {
        List {
            if let error {
                Text(verbatim: error).foregroundStyle(Theme.ink2)
                Button("Retry") { Task { await load() } }.frame(minHeight: 44)
            }
            if !loaded { ProgressView().frame(maxWidth: .infinity) }
            if loaded, notes.isEmpty { Text("No notes yet") }
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: note.body).textSelection(.enabled)
                    Text(verbatim: note.bossName).font(.caption).foregroundStyle(Theme.ink2)
                    timestamp(note.createdAt)
                    HStack {
                        if note.status == .pending { Text("Unread") }
                        else { Text("Read") }
                        if let readAt = note.readAt { timestamp(readAt) }
                    }.font(.caption).foregroundStyle(Theme.ink2)
                }.padding(.vertical, 4)
            }
        }
        .navigationTitle("Session notes")
        .safeAreaInset(edge: .bottom) {
            if canCreate {
                Button("Leave a note") { composing = true }
                    .frame(maxWidth: .infinity, minHeight: 44).prominentAction()
                    .padding().background(.bar).accessibilityIdentifier("compose-session-note")
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $composing) {
            SessionNoteComposer(sessionID: sessionID, api: api) { note in
                notes.removeAll { $0.id == note.id }
                notes.insert(note, at: 0)
            }
        }
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
                .sorted { $0.createdAt > $1.createdAt }
            loaded = true
            canCreate = try await api.canCreateSessionNotes()
        } catch { self.error = error.localizedDescription }
    }
}

private struct SessionNoteComposer: View {
    let sessionID: String
    let api: any SessionNotesServing
    let onSent: (SessionNote) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var bodyText = ""
    @State private var sending = false
    @State private var error: String?
    @State private var attempt: (body: String, key: String)?
    private var trimmed: String { bodyText.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Write a note…", text: $bodyText, axis: .vertical)
                    .lineLimit(6...12).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("session-note-body").disabled(sending)
                    .onChange(of: bodyText) { _, value in
                        if value.unicodeScalars.count > 4000 {
                            bodyText = String(String.UnicodeScalarView(value.unicodeScalars.prefix(4000)))
                        }
                    }
                Text(verbatim: "\(bodyText.unicodeScalars.count) / 4000").font(.caption).foregroundStyle(Theme.ink2)
                if let error { Text(verbatim: error).foregroundStyle(Theme.ink2) }
                Spacer()
                Button(action: send) {
                    HStack {
                        if sending { ProgressView() }
                        Text("Send note")
                    }.frame(maxWidth: .infinity, minHeight: 44)
                }.prominentAction().disabled(sending || trimmed.isEmpty)
                    .accessibilityIdentifier("send-session-note")
            }
            .padding().background(Theme.paper).navigationTitle("Leave a note")
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }.frame(minWidth: 44, minHeight: 44).disabled(sending)
            } }
        }.interactiveDismissDisabled(sending)
    }

    private func send() {
        guard !sending, !trimmed.isEmpty, trimmed.unicodeScalars.count <= 4000 else { return }
        if attempt?.body != trimmed { attempt = (trimmed, UUID().uuidString) }
        guard let attempt else { return }
        sending = true
        error = nil
        Task {
            defer { sending = false }
            do {
                let note = try await api.createSessionNote(
                    sessionID: sessionID, body: attempt.body, idempotencyKey: attempt.key)
                onSent(note)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
