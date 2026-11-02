// Boss-side note bubble for the session transcript, with authenticated images and receipts.
// Uses HibossKit notes and the existing full-screen image viewer.
import HibossKit
import SwiftUI

struct SessionNoteBubble: View {
    let note: SessionNote
    let api: any SessionNotesServing

    var body: some View {
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

    private func timestamp(_ value: String) -> some View {
        Group {
            if let date = ISODate.parse(value) { Text(date, format: .dateTime.month().day().hour().minute()) }
            else { Text(verbatim: value) }
        }.font(.caption).foregroundStyle(Theme.ink2)
    }

}

enum SessionNoteQuote {
    static func text(for messageID: String, notes: [SessionNote]) -> String? {
        guard let note = notes.first(where: { $0.replies.contains { $0.messageID == messageID } })
        else { return nil }
        return String(note.body.split(separator: "\n", omittingEmptySubsequences: false).first ?? "")
    }
}
