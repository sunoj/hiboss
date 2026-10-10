// Rounded-square project placeholders and unauthenticated avatar image presentation.
// Exports: ProjectAvatarView(project:size:) and ProjectAvatarContent.
// Dependencies: SwiftUI, HibossKit placeholder rules, and named brand colour assets.

import HibossKit
import SwiftUI

struct ProjectAvatarView: View {
    let project: ProjectIdentity
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 32
    @StateObject private var loader = ProjectAvatarLoader()

    init(project: ProjectIdentity, size: CGFloat) {
        self.project = project
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    var body: some View {
        ProjectAvatarContent(placeholder: project.placeholder, image: loader.image, size: size)
            .accessibilityHidden(true)
            .task(id: project.avatarURL) { await loader.load(project.avatarURL) }
    }
}

struct ProjectAvatarContent: View {
    let placeholder: ProjectAvatarPlaceholder
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        ZStack {
            Color(placeholder.tint.assetName, bundle: appResourceBundle)
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Text(verbatim: placeholder.initial).font(.caption.bold()).foregroundStyle(.white)
                    .minimumScaleFactor(0.5).lineLimit(1).padding(size * 0.18)
            }
        }
        .frame(width: size, height: size).compositingGroup().clipShape(shape)
        .accessibilityHidden(true)
    }
}

extension ProjectAvatarPlaceholder.Tint {
    var assetName: String {
        switch self {
        case .sky: "AvatarSky"
        case .lagoon: "AvatarLagoon"
        case .sand: "AvatarSand"
        case .palm: "AvatarPalm"
        case .coral: "AvatarCoral"
        case .violet: "AvatarViolet"
        case .slate: "AvatarSlate"
        case .amber: "AvatarAmber"
        }
    }
}
