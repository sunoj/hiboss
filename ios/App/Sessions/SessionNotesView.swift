// Session notes list and inline composer with retry-safe submission.
// Exports SessionNotesView, using SessionNotesServing and native Theme styles.
// Dependencies: SwiftUI and HibossKit.

import Foundation
import HibossKit
import SwiftUI

struct SessionNotesView: View {
    let sessionID: String
    let api: any SessionNotesServing
    @Environment(\.scenePhase) private var scenePhase
    @State private var notes: [SessionNote] = []
    @State private var canCreate = false
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        timeline
        .navigationTitle("Session notes")
        .safeAreaInset(edge: .bottom) {
            if canCreate {
                SessionNoteComposer(sessionID: sessionID, api: api) { note in
                    notes.removeAll { $0.id == note.id }
                    notes.append(note)
                }
            }
        }
        .task {
            SessionNoteReadState.open(sessionID)
            await load()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
        .refreshable { await load() }
    }

    private var timeline: some View {
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
                        noteBubble(note)
                        ForEach(note.replies) { reply in replyBubble(reply) }
                    }
                    Color.clear.frame(height: 1).id("newest")
                }.padding()
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: notes) { _, _ in proxy.scrollTo("newest", anchor: .bottom) }
        }
    }

    private func noteBubble(_ note: SessionNote) -> some View {
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

    private func replyBubble(_ reply: SessionNoteReply) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: reply.body).textSelection(.enabled)
            HStack(spacing: 4) {
                Text(verbatim: reply.agentName)
                Text(verbatim: "·")
                timestamp(reply.createdAt)
            }.font(.caption).foregroundStyle(Theme.ink2)
        }
        .padding(12).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 32)
        .accessibilityIdentifier("note-reply-\(reply.messageID)")
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

enum SessionNoteReadState {
    static func open(_ sessionID: String, defaults: UserDefaults = .standard, now: Date = .now) {
        defaults.set(now.timeIntervalSince1970, forKey: key(sessionID))
    }

    static func hasNewReplies(_ notes: [SessionNote], sessionID: String,
                              defaults: UserDefaults = .standard) -> Bool {
        let opened = defaults.double(forKey: key(sessionID))
        return notes.flatMap(\.replies).contains {
            guard let date = ISODate.parse($0.createdAt) else { return false }
            return date.timeIntervalSince1970 > opened
        }
    }

    private static func key(_ sessionID: String) -> String { "session-notes-opened.\(sessionID)" }
}
