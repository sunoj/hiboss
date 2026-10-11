// Circular registered agent images with existing initials while loading or on failure.
// Exports AgentAvatarView and AgentAvatarContent; depends on the shared lookup and AsyncImage.

import HibossKit
import SwiftUI

struct AgentAvatarView: View {
    let name: String
    let size: CGFloat
    @Environment(\.agentAvatars) private var avatars

    var body: some View {
        let url = avatars?.url(for: name)
        if isDemoMode, url == AgentAvatarDemo.url, let image = AgentAvatarDemo.image {
            AgentAvatarContent(name: name, size: size, phase: .success(image))
        } else {
            AsyncImage(url: url) { phase in
                AgentAvatarContent(name: name, size: size, phase: phase)
            }
            .id(url)
        }
    }
}

struct AgentAvatarContent: View {
    let name: String
    let size: CGFloat
    let phase: AsyncImagePhase

    var body: some View {
        if case let .success(image) = phase {
            image.resizable().scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .accessibilityHidden(true)
        } else {
            initials
        }
    }

    private var initials: some View {
        Text(verbatim: HistoryMessage.avatarInitials(agentName: name))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.ink2)
            .minimumScaleFactor(0.5).lineLimit(1)
            .frame(width: size, height: size)
            .background(Theme.surface2, in: Circle())
            .accessibilityHidden(true)
    }
}
