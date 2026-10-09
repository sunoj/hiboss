// Bottom thread reply field with an explicit eligible target retained while drafting.
// Exports SessionReplyComposer; Box references remain visible in the editable reply.
// Dependencies: InboxStore reply receipts, BoxListView picker, and native text controls.

import HibossKit
import SwiftUI

struct SessionReplyComposer: View {
    let targets: [SessionReplyTarget]
    @ObservedObject var store: InboxStore
    @State private var replyDraft = SessionReplyDraft()
    @State private var picking = false
    @State private var note: String?

    private var target: SessionReplyTarget? { replyDraft.target(in: targets) }
    private var submitting: Bool { target.map { store.replying[$0.id] != nil } ?? false }
    private var draft: Binding<String> {
        Binding(get: { replyDraft.text }, set: { replyDraft.update($0, targets: targets) })
    }
    private var boxAPI: (any BoxServing)? {
        isDemoMode ? DemoBoxAPI.shared : store.api as? any BoxServing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            targetLabel
            if let newer = replyDraft.newer(in: targets) {
                Button("Reply to the newer message") { replyDraft.select(newer) }
                    .font(.footnote).frame(minHeight: 44).disabled(submitting)
            }
            if target == nil, replyDraft.pinned != nil {
                Button("Discard draft") { replyDraft = SessionReplyDraft() }
                    .frame(minHeight: 44)
            }
            if let note { Text(verbatim: note).font(.footnote).foregroundStyle(Theme.ink2) }
            HStack(alignment: .bottom, spacing: 8) {
                Button { picking = true } label: {
                    Image(systemName: "plus").frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("Attach from Box")
                    .disabled(target == nil || submitting)
                TextField("Reply to session…", text: draft, axis: .vertical)
                    .lineLimit(1...5).textFieldStyle(.roundedBorder)
                    .frame(minHeight: 44).accessibilityIdentifier("session-reply-draft")
                    .disabled(target == nil || submitting)
                Button(action: send) {
                    if submitting { DelayedProgressView() }
                    else { Image(systemName: "arrow.up").frame(minWidth: 44, minHeight: 44) }
                }.prominentAction().tint(Theme.primaryAction).accessibilityLabel("Send reply")
                    .disabled(target == nil || submitting
                              || replyDraft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private var targetLabel: some View {
        Group {
            if let target {
                Text(verbatim: target.label)
            } else if replyDraft.pinned != nil {
                Text("This draft's target is unavailable. Discard it or choose a newer message.")
            } else {
                Text("No eligible agent message. Resolved decisions cannot receive replies.")
            }
        }
        .font(.footnote).foregroundStyle(Theme.ink2)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("session-reply-target")
    }

    private func attach(_ item: BoxItem) {
        let reference = [item.boxTitle, item.url, "box:\(item.id)"].compactMap { $0 }.joined(separator: " · ")
        replyDraft.update(replyDraft.text + (replyDraft.text.isEmpty ? "" : "\n") + reference,
                          targets: targets)
        picking = false
    }

    private func send() {
        guard let target, !submitting else { return }
        let text = replyDraft.text
        Task {
            switch await store.reply(text, to: target.id) {
            case .sent:
                replyDraft = SessionReplyDraft()
                note = String(localized: "Reply sent.")
            case .busy: break
            case .alreadyResolved: note = String(localized: "That decision was already answered elsewhere.")
            case .failed: note = String(localized: "Couldn't send your reply — check your connection.")
            }
        }
    }
}

// Candidate projection and draft state share one contract with the composer tests.
struct SessionReplyTarget: Equatable {
    let id: MessageID
    let sequence: Int
    let text: String
    let isDecision: Bool

    var label: String {
        isDecision ? String(localized: "Custom answer to: \(text)")
            : String(localized: "Replying to: \(text)")
    }

    @MainActor
    static func eligible(events: [SessionEvent], store: InboxStore) -> [Self] {
        let openIDs = Set(store.todaySnapshot(now: .now).decisions.map(\.id))
        return events.compactMap { event in
            guard event.kind == "message", event.direction == "agent_to_boss",
                  let raw = event.messageId else { return nil }
            let id = MessageID(rawValue: raw)
            let message = store.requiredInputs.first { $0.id == id } ?? store.message(for: id)
            let payload = event.payload?.objectValue
            let hasOptions: Bool
            if case let .array(options)? = payload?["options"] { hasOptions = !options.isEmpty }
            else { hasOptions = false }
            let decision = openIDs.contains(id) || message?.isDecision == true || message?.mode == "blocking"
                || hasOptions || payload?["type"] == .string("approval_request")
                || payload?["mode"] == .string("blocking")
            if decision && (!openIDs.contains(id) || store.settlement(for: id) != nil) { return nil }
            let body = message?.body ?? event.displayBody
            let text = decision ? body : String(body.split(separator: "\n", omittingEmptySubsequences: false)
                .first ?? "")
            return Self(id: id, sequence: event.sequence, text: text, isDecision: decision)
        }.sorted { $0.sequence < $1.sequence }
    }
}

struct SessionReplyDraft {
    private(set) var text = ""
    private(set) var pinned: SessionReplyTarget?

    func target(in targets: [SessionReplyTarget]) -> SessionReplyTarget? {
        guard let pinned else { return targets.last }
        return targets.contains { $0.id == pinned.id } ? pinned : nil
    }

    func newer(in targets: [SessionReplyTarget]) -> SessionReplyTarget? {
        guard let pinned, let newest = targets.last,
              newest.id != pinned.id, newest.sequence > pinned.sequence else { return nil }
        return newest
    }

    mutating func update(_ text: String, targets: [SessionReplyTarget]) {
        if self.text.isEmpty && !text.isEmpty { pinned = targets.last }
        self.text = text
        if text.isEmpty { pinned = nil }
    }

    mutating func select(_ target: SessionReplyTarget) {
        pinned = text.isEmpty ? nil : target
    }
}
