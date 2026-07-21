// Section header for session-grouped inbox history lists.
// Exports: SessionSectionHeader showing status, label, and message count.
// Dependencies: SwiftUI, HibossKit SessionGroup, theme tokens.

import HibossKit
import SwiftUI

struct SessionSectionHeader: View {
    let group: SessionGroup

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .accessibilityLabel(statusAccessibilityLabel)

            Text(group.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text("\(group.messages.count)")
                .font(.hbMonoSmall)
                .foregroundStyle(Theme.ink3)
                .monospacedDigit()
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch group.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "working": Theme.positive
        case "waiting", "blocked": Theme.warn
        default: Theme.ink4
        }
    }

    private var statusAccessibilityLabel: String {
        let cleaned = group.status?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleaned.isEmpty ? "Session status unknown" : "Session \(cleaned)"
    }
}
