// Circular registered avatars with cached images or initials while public images load.
// Exports AgentAvatarView and AgentAvatarContent; depends on the shared account lookup.

import HibossKit
import SwiftUI

struct AgentAvatarView: View {
    let name: String
    let size: CGFloat
    let lookupName: String?
    @Environment(\.agentAvatars) private var avatars

    init(name: String, size: CGFloat) {
        self.init(name: name, size: size, lookupName: name)
    }

    init(name: String, size: CGFloat, lookupName: String?) {
        self.name = name
        self.size = size
        self.lookupName = lookupName.flatMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
        }
    }

    var body: some View {
        let url = lookupName.flatMap { avatars?.url(forName: $0) }
        if ProcessInfo.processInfo.environment["HIBOSS_ATTENTION_PREVIEW"] != nil,
           url == AgentAvatarDemo.url, let image = AgentAvatarDemo.image {
            AgentAvatarContent(name: name, size: size, phase: .success(image))
        } else {
            LoadedAgentAvatar(name: name, size: size, url: url).id(url)
        }
    }
}

private struct LoadedAgentAvatar: View {
    let name: String
    let size: CGFloat
    let url: URL?
    @StateObject private var loader: ProjectAvatarLoader

    init(name: String, size: CGFloat, url: URL?) {
        self.name = name
        self.size = size
        self.url = url
        _loader = StateObject(wrappedValue: ProjectAvatarLoader(url: url))
    }

    var body: some View {
        AgentAvatarContent(name: name, size: size,
            phase: loader.image.map { .success(Image(nsImage: $0)) } ?? .empty)
            .task(id: url) { await loader.load(url) }
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
        Text(HistoryMessage.monogram(agentName: name, isBossMessage: false))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .minimumScaleFactor(0.5).lineLimit(1)
            .frame(width: size, height: size)
            .background(Color.primary.opacity(0.05), in: Circle())
            .accessibilityHidden(true)
    }
}
