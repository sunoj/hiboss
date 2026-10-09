// Bottom thread reply field targeting the newest agent message in the session.
// Exports SessionReplyComposer; Box references remain visible in the editable reply.
// Dependencies: InboxStore reply receipts, BoxListView picker, and native text controls.

import HibossKit
import SwiftUI

struct SessionReplyComposer: View {
    let target: MessageID?
    @ObservedObject var store: InboxStore
    @State private var draft = ""
    @State private var picking = false
    @State private var note: String?

    private var submitting: Bool { target.map { store.replying[$0] != nil } ?? false }
    private var boxAPI: (any BoxServing)? {
        isDemoMode ? DemoBoxAPI.shared : store.api as? any BoxServing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if target == nil {
                Text("No agent message yet. Reply will be available when one arrives.")
                    .font(.footnote).foregroundStyle(Theme.ink2)
            }
            if let note { Text(verbatim: note).font(.footnote).foregroundStyle(Theme.ink2) }
            HStack(alignment: .bottom, spacing: 8) {
                Button { picking = true } label: {
                    Image(systemName: "plus").frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("Attach from Box")
                    .disabled(target == nil || submitting)
                TextField("Reply to session…", text: $draft, axis: .vertical)
                    .lineLimit(1...5).textFieldStyle(.roundedBorder)
                    .frame(minHeight: 44).accessibilityIdentifier("session-reply-draft")
                    .disabled(target == nil || submitting)
                Button(action: send) {
                    if submitting { DelayedProgressView() }
                    else { Image(systemName: "arrow.up").frame(minWidth: 44, minHeight: 44) }
                }.prominentAction().tint(Theme.primaryAction).accessibilityLabel("Send reply")
                    .disabled(target == nil || submitting
                              || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12).background(.bar)
        .sheet(isPresented: $picking) {
            NavigationStack {
                BoxListView(api: boxAPI, onSelect: attach)
                    .navigationTitle("Attach from Box")
                    .toolbar { ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { picking = false }
                    } }
            }
        }
    }

    private func attach(_ item: BoxItem) {
        let reference = [item.boxTitle, item.url, "box:\(item.id)"].compactMap { $0 }.joined(separator: " · ")
        draft += (draft.isEmpty ? "" : "\n") + reference
        picking = false
    }

    private func send() {
        guard let target, !submitting else { return }
        let text = draft
        Task {
            switch await store.reply(text, to: target) {
            case .sent:
                draft = ""
                note = String(localized: "Reply sent.")
            case .busy: break
            case .alreadyResolved: note = String(localized: "That decision was already answered elsewhere.")
            case .failed: note = String(localized: "Couldn't send your reply — check your connection.")
            }
        }
    }
}
