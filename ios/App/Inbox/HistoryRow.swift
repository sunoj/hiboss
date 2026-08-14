// Compact history row in the Inbox list, following iOS Messages.
// Exports: HistoryRow rendering one HistoryMessage as a native list row.
// Dependencies: SwiftUI, HibossKit.

import HibossKit
import SwiftUI

struct HistoryRow: View {
    let message: HistoryMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(message.avatarInitials)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(Color(.tertiarySystemFill), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(message.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if !message.relativeCreatedAt.isEmpty {
                        Text(message.relativeCreatedAt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(message.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                MessageMetaStrip(message: message, density: .row)
                if !statusLabel.isEmpty {
                    Text(statusLabel)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var statusLabel: String {
        message.status.isEmpty ? "" : message.status.capitalized
    }

    private var statusColor: Color {
        switch message.status {
        case "replied": .green
        case "expired": .orange
        default: .secondary
        }
    }
}
