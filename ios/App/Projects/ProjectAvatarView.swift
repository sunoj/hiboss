// Canonical project avatar with a deterministic shape and initial while images load or fail.
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
            if case let .success(image) = phase {
                image.resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipShape(ProjectAvatarShape(kind: placeholder.shape))
            } else {
                ProjectAvatarShape(kind: placeholder.shape).fill(placeholder.tint.avatarColor)
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

struct ProjectAvatarShape: Shape {
    let kind: ProjectAvatarPlaceholder.Shape

    func path(in rect: CGRect) -> Path {
        switch kind {
        case .circle: return Circle().path(in: rect)
        case .roundedSquare:
            return RoundedRectangle(cornerRadius: rect.width * 0.24).path(in: rect)
        case .diamond:
            return polygon(in: rect, points: [(0.5, 0), (1, 0.5), (0.5, 1), (0, 0.5)])
        case .hexagon:
            return polygon(in: rect, points: [(0.25, 0), (0.75, 0), (1, 0.5),
                                               (0.75, 1), (0.25, 1), (0, 0.5)])
        }
    }

    private func polygon(in rect: CGRect, points: [(CGFloat, CGFloat)]) -> Path {
        Path { path in
            for (index, point) in points.enumerated() {
                let vertex = CGPoint(x: rect.minX + point.0 * rect.width,
                                     y: rect.minY + point.1 * rect.height)
                if index == 0 { path.move(to: vertex) } else { path.addLine(to: vertex) }
            }
            path.closeSubpath()
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
