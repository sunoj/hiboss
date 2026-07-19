// Compact history row for the "All" list and the Messages tab.
// Exports: HistoryRow rendering one HistoryMessage.
// Dependencies: SwiftUI, HibossKit, theme tokens.

import HibossKit
import SwiftUI

struct HistoryRow: View {
    let message: HistoryMessage

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Circle()
                .fill(message.priorityValue.color)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(message.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Text(message.metaLine)
                        .font(.hbMonoSmall)
                        .foregroundStyle(Theme.ink3)
                    Spacer(minLength: 4)
                    Text(message.status)
                        .font(.hbMonoSmall)
                        .foregroundStyle(statusColor)
                }
                Text(message.body)
                    .font(.hbSmall)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }

    private var statusColor: Color {
        switch message.status {
        case "replied": Theme.positive
        case "expired": Theme.ink4
        default: Theme.ink3
        }
    }
}
