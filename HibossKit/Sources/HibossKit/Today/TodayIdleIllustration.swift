// Draws the compact all-clear island directly in native interface colours.
// Exports TodayIdleIllustration; transparent line art is shared by iOS and macOS.
// Dependencies: SwiftUI Canvas with no raster assets or animation timer.

import SwiftUI

public struct TodayIdleIllustration: View {
    private let ink: Color
    private let accent: Color

    public init(ink: Color = .primary, accent: Color = .green) {
        self.ink = ink
        self.accent = accent
    }

    public var body: some View {
        Canvas { context, _ in
            let island = Path(ellipseIn: CGRect(x: 21, y: 48, width: 83, height: 14))
            context.fill(island, with: .color(accent.opacity(0.09)))
            context.stroke(island, with: .color(ink.opacity(0.25)), lineWidth: 1)
            drawPalm(in: &context)
            drawChair(in: &context)
            let sun = Path(ellipseIn: CGRect(x: 82, y: 9, width: 10, height: 10))
            context.fill(sun, with: .color(accent.opacity(0.18)))
            let water = Path { path in
                path.move(to: CGPoint(x: 6, y: 60))
                path.addQuadCurve(to: CGPoint(x: 25, y: 60), control: CGPoint(x: 15, y: 57))
                path.move(to: CGPoint(x: 95, y: 66))
                path.addQuadCurve(to: CGPoint(x: 114, y: 66), control: CGPoint(x: 104, y: 63))
            }
            context.stroke(water, with: .color(ink.opacity(0.2)), lineWidth: 1)
        }
        .frame(width: 120, height: 72)
        .accessibilityHidden(true)
    }

    private func drawPalm(in context: inout GraphicsContext) {
        let trunk = Path { path in
            path.move(to: CGPoint(x: 43, y: 52))
            path.addQuadCurve(to: CGPoint(x: 53, y: 23), control: CGPoint(x: 41, y: 35))
        }
        context.stroke(trunk, with: .color(ink.opacity(0.65)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
        for tip in [CGPoint(x: 30, y: 20), CGPoint(x: 40, y: 10),
                    CGPoint(x: 74, y: 15), CGPoint(x: 78, y: 29)] {
            let leaf = Path { path in
                path.move(to: CGPoint(x: 53, y: 23))
                path.addQuadCurve(to: tip, control: CGPoint(x: (53 + tip.x) / 2, y: tip.y - 6))
                path.addQuadCurve(to: CGPoint(x: 53, y: 23),
                                  control: CGPoint(x: (53 + tip.x) / 2, y: tip.y + 2))
                path.closeSubpath()
            }
            context.fill(leaf, with: .color(accent.opacity(0.55)))
        }
    }

    private func drawChair(in context: inout GraphicsContext) {
        let fabric = Path { path in
            path.move(to: CGPoint(x: 68, y: 48))
            path.addLine(to: CGPoint(x: 75, y: 32))
            path.addLine(to: CGPoint(x: 86, y: 35))
            path.addLine(to: CGPoint(x: 80, y: 48))
            path.closeSubpath()
        }
        context.fill(fabric, with: .color(ink.opacity(0.08)))
        let frame = Path { path in
            path.move(to: CGPoint(x: 65, y: 54))
            path.addLine(to: CGPoint(x: 75, y: 32))
            path.addLine(to: CGPoint(x: 86, y: 35))
            path.move(to: CGPoint(x: 68, y: 48))
            path.addLine(to: CGPoint(x: 95, y: 51))
            path.move(to: CGPoint(x: 81, y: 49))
            path.addLine(to: CGPoint(x: 84, y: 55))
        }
        context.stroke(frame, with: .color(ink.opacity(0.6)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }
}
