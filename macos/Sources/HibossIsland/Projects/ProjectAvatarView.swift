// Shared project placeholder shapes and unauthenticated avatar image presentation.
// Exports: ProjectAvatarView(project:size:) and ProjectAvatarShape.
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
        let placeholder = project.placeholder
        let shape = ProjectAvatarShape(kind: placeholder.shape)
        ZStack {
            shape.fill(Color(placeholder.tint.assetName, bundle: appResourceBundle))
            if let image = loader.image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Text(verbatim: placeholder.initial).font(.caption.bold()).foregroundStyle(.white)
                    .minimumScaleFactor(0.5).lineLimit(1).padding(size * 0.18)
            }
        }
        .frame(width: size, height: size).clipShape(shape)
        .accessibilityHidden(true)
        .task(id: project.avatarURL) { await loader.load(project.avatarURL) }
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

struct ProjectAvatarShape: Shape {
    let kind: ProjectAvatarPlaceholder.Shape

    func path(in rect: CGRect) -> Path {
        switch kind {
        case .circle: return Circle().path(in: rect)
        case .roundedSquare:
            return RoundedRectangle(cornerRadius: rect.width * 0.22).path(in: rect)
        case .diamond:
            return polygon(in: rect, points: [(0.5, 0), (1, 0.5), (0.5, 1), (0, 0.5)])
        case .hexagon:
            return polygon(in: rect, points: [(0.25, 0), (0.75, 0), (1, 0.5),
                (0.75, 1), (0.25, 1), (0, 0.5)])
        }
    }

    private func polygon(in rect: CGRect, points: [(CGFloat, CGFloat)]) -> Path {
        Path { path in
            path.addLines(points.map { CGPoint(x: rect.minX + $0.0 * rect.width,
                y: rect.minY + $0.1 * rect.height) })
            path.closeSubpath()
        }
    }
}
