// Canonical rounded-square project avatar with a stable tint and initial while images load or fail.
// Exports ProjectAvatarView; depends on SwiftUI AsyncImage and HibossKit project identity.

import HibossKit
import SwiftUI

struct ProjectAvatarView: View {
    let project: ProjectIdentity
    let size: CGFloat

    var body: some View {
        AsyncImage(url: imageURL) { phase in
            ProjectAvatarContent(placeholder: project.placeholder, phase: phase)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var imageURL: URL? {
        guard let url = project.avatarURL, url.host != nil,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        // AsyncImage uses an ordinary image request, without the boss API's authorization header.
        return url
    }
}

struct ProjectAvatarContent: View {
    let placeholder: ProjectAvatarPlaceholder
    let phase: AsyncImagePhase

    var body: some View {
        GeometryReader { geometry in
            let shape = RoundedRectangle(cornerRadius: geometry.size.width * 0.22, style: .continuous)
            if case let .success(image) = phase {
                image.resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipShape(shape)
            } else {
                shape.fill(placeholder.tint.avatarColor)
                    .overlay {
                        Text(verbatim: placeholder.initial).font(.caption.bold())
                            .foregroundStyle(Color("AvatarInitial"))
                            .minimumScaleFactor(0.5).lineLimit(1)
                            .padding(geometry.size.width * 0.2)
                    }
            }
        }
    }
}

extension ProjectAvatarPlaceholder.Tint {
    var avatarColor: Color {
        switch self {
        case .sky: Color("AvatarSky")
        case .lagoon: Color("AvatarLagoon")
        case .sand: Color("AvatarSand")
        case .palm: Color("AvatarPalm")
        case .coral: Color("AvatarCoral")
        case .violet: Color("AvatarViolet")
        case .slate: Color("AvatarSlate")
        case .amber: Color("AvatarAmber")
        }
    }
}
