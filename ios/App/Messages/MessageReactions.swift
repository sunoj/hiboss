// Read-only emoji summaries shared by message bodies and thread entries.
// Exports MessageReactions; depends on HibossKit reactionGroups and semantic styles.

import HibossKit
import SwiftUI

struct MessageReactions: View {
    let message: HistoryMessage

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips }
            VStack(alignment: .leading, spacing: 6) { chips }
        }
    }

    private var chips: some View {
        ForEach(message.metadata?.reactionGroups ?? [], id: \.emoji) { group in
            Text(verbatim: group.emoji + (group.count > 1 ? " \(group.count)" : ""))
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.surface2, in: Capsule())
                .accessibilityLabel(Text("\(group.emoji), \(group.count) reactions"))
                .accessibilityIdentifier("reaction-\(message.id.rawValue)-\(group.emoji)")
        }
    }
}
