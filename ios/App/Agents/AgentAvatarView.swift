// Circular agent initials for session and peer attribution.
// Exports AgentAvatarView; depends on the existing HistoryMessage initials and semantic Theme tokens.

import HibossKit
import SwiftUI

struct AgentAvatarView: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Text(verbatim: HistoryMessage.avatarInitials(agentName: name))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.ink2)
            .minimumScaleFactor(0.5).lineLimit(1)
            .frame(width: size, height: size)
            .background(Theme.surface2, in: Circle())
            .accessibilityHidden(true)
    }
}
