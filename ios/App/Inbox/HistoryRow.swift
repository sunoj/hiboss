// Compact history row for the "All" list and the Messages tab.
// Exports: HistoryRow rendering one HistoryMessage as a native list row.
// Dependencies: SwiftUI, HibossKit.

import HibossKit
import SwiftUI

struct HistoryRow: View {
    let message: HistoryMessage

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Circle()
                .fill(message.priorityValue.color)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(message.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(message.metaLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(message.status)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
                Text(message.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        switch message.status {
        case "replied": .green
        default: .secondary
        }
    }
}
