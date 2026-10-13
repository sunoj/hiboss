// Selectable replies in server order, nested beneath their agent message.
// Exports: HistoryReplies; folded replies never have a Details disclosure.
// Dependencies: SwiftUI, HibossKit, SharedTimestamp, AnswerSource, and localized attribution.

import HibossKit
import SwiftUI

struct HistoryReplies: View {
    let replies: [HistoryMessage]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(replies) { reply in
                HStack(alignment: .top, spacing: 12) {
                    Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
                    VStack(alignment: .leading, spacing: 4) {
                        attribution(reply)
                        Text(reply.body).font(.body).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true).padding(.leading, 8)
            }
        }
    }

    private func attribution(_ reply: HistoryMessage) -> some View {
        HStack(spacing: 6) {
            if reply.metadata?.isAutoDefault == true {
                Label(L("Auto-selected when time ran out"), systemImage: "clock.arrow.circlepath")
            } else {
                Text(L("Me"))
            }
            TimelineView(.periodic(from: .now, by: 60)) { tick in
                Text(ISODate.parse(reply.createdAt).map { SharedTimestamp.string($0, now: tick.date) }
                    ?? L("Unknown"))
                    .frame(width: 160, alignment: .leading)
            }
            if let source = reply.metadata?.answeredBy?.displayLabel
                ?? reply.metadata?.source.flatMap(AnswerSource.visibleLabel),
               !source.isEmpty {
                Text(verbatim: source)
            }
        }
        .font(.caption).foregroundStyle(.secondary)
    }
}
