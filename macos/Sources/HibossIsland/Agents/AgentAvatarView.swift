// Circular agent initials for session and peer attribution.
// Exports AgentAvatarView; depends on the existing HistoryMessage monogram and semantic system colours.

import HibossKit
import SwiftUI

struct AgentAvatarView: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Text(HistoryMessage.monogram(agentName: name, isBossMessage: false))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .minimumScaleFactor(0.5).lineLimit(1)
            .frame(width: size, height: size)
            .background(Color.primary.opacity(0.05), in: Circle())
            .accessibilityHidden(true)
    }
}
