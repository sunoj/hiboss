// Empty-state island: a flat reading of the app icon for all-clear surfaces.
// Exports: AllClearIslandView, AllClearIslandMotion, IslandSwatch.
// Dependencies: SwiftUI TimelineView + Canvas; colours from the asset catalog.

import SwiftUI

enum IslandSwatch {
    static let sky = Color("IslandSky")
    static let horizon = Color("IslandHorizon")
    static let water = Color("IslandWater")
    static let shimmer = Color("IslandWaterShimmer")
    static let sand = Color("IslandSand")
    static let palm = Color("IslandPalm")
    static let trunk = Color("IslandTrunk")
    static let skin = Color("IslandSkin")
    static let hair = Color("IslandHair")
    static let shirt = Color("IslandShirt")
    static let ink = Color("IslandInk")

    static let names = [
        "IslandSky", "IslandHorizon", "IslandWater", "IslandWaterShimmer",
        "IslandSand", "IslandPalm", "IslandTrunk", "IslandSkin",
        "IslandHair", "IslandShirt", "IslandInk",
    ]
}

enum AllClearIslandMotion {
    struct Phase: Equatable {
        var breathe: CGFloat
        var frond: CGFloat
        var shimmer: CGFloat
    }

    /// Still pose when Reduce Motion is on; otherwise slow endless cycles.
    static func phase(at date: Date, reducedMotion: Bool) -> Phase {
        if reducedMotion { return Phase(breathe: 0, frond: 0, shimmer: 0.35) }
        let t = date.timeIntervalSinceReferenceDate
        return Phase(
            breathe: CGFloat(sin(t * 2 * .pi / 7)),
            frond: CGFloat(sin(t * 2 * .pi / 5.5) * 0.10),
            shimmer: CGFloat((sin(t * 2 * .pi / 3.8) + 1) / 2)
        )
    }
}

struct AllClearIslandView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let phase = AllClearIslandMotion.phase(at: context.date, reducedMotion: reduceMotion)
            Canvas { canvas, size in
                AllClearIslandScene.draw(in: &canvas, size: size, phase: phase)
            }
        }
        .frame(width: 168, height: 148)
        .accessibilityHidden(true)
    }
}

enum AllClearIslandScene {
    static func draw(in context: inout GraphicsContext, size: CGSize, phase: AllClearIslandMotion.Phase) {
        let cx = size.width * 0.5
        context.translateBy(x: 0, y: phase.breathe * 2)
        drawSky(in: &context, size: size)
        drawWater(in: &context, cx: cx, size: size, shimmer: phase.shimmer)
        drawSand(in: &context, cx: cx, size: size)
        drawPalm(in: &context, origin: CGPoint(x: cx - 26, y: size.height * 0.66), sway: phase.frond)
        drawLounge(in: &context, origin: CGPoint(x: cx + 8, y: size.height * 0.60))
        drawLaptop(in: &context, origin: CGPoint(x: cx + 40, y: size.height * 0.70))
    }

    static func leaf(from origin: CGPoint, length: CGFloat, angle: CGFloat, width: CGFloat) -> Path {
        Path { path in
            let tip = CGPoint(x: origin.x + length * cos(angle), y: origin.y + length * sin(angle))
            let mid = CGPoint(x: (origin.x + tip.x) / 2, y: (origin.y + tip.y) / 2)
            let nx = -sin(angle) * width, ny = cos(angle) * width
            path.move(to: origin)
            path.addQuadCurve(to: tip, control: CGPoint(x: mid.x + nx, y: mid.y + ny))
            path.addQuadCurve(to: origin, control: CGPoint(x: mid.x - nx, y: mid.y - ny))
            path.closeSubpath()
        }
    }
}

private extension AllClearIslandScene {
    static func drawSky(in context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(x: (size.width - 140) / 2, y: 4, width: 140, height: 140)
        let world = Path(ellipseIn: rect)
        context.fill(world, with: .linearGradient(
            Gradient(colors: [IslandSwatch.sky, IslandSwatch.horizon]),
            startPoint: CGPoint(x: rect.midX, y: rect.minY),
            endPoint: CGPoint(x: rect.midX, y: rect.midY + 12)
        ))
    }

    static func drawWater(in context: inout GraphicsContext, cx: CGFloat, size: CGSize, shimmer: CGFloat) {
        let water = CGRect(x: cx - 66, y: size.height * 0.42, width: 132, height: 78)
        context.fill(Path(ellipseIn: water), with: .color(IslandSwatch.water))
        let near = 0.16 + 0.22 * shimmer
        let far = 0.12 + 0.18 * (1 - shimmer)
        strokeRipple(in: &context, cx: cx, cy: water.midY - 4, w: 88 + 8 * shimmer, h: 36, opacity: near)
        strokeRipple(in: &context, cx: cx, cy: water.midY - 2, w: 112, h: 50, opacity: far)
        let glint = CGRect(x: cx - 40, y: water.minY + 10, width: 36, height: 14)
        context.opacity = 0.22 + 0.12 * shimmer
        context.fill(Path(ellipseIn: glint), with: .color(IslandSwatch.shimmer))
        context.opacity = 1
    }

    static func strokeRipple(
        in context: inout GraphicsContext, cx: CGFloat, cy: CGFloat,
        w: CGFloat, h: CGFloat, opacity: CGFloat
    ) {
        let rect = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
        context.opacity = opacity
        context.stroke(Path(ellipseIn: rect), with: .color(IslandSwatch.shimmer), lineWidth: 1.2)
        context.opacity = 1
    }

    static func drawSand(in context: inout GraphicsContext, cx: CGFloat, size: CGSize) {
        let island = CGRect(x: cx - 40, y: size.height * 0.60, width: 80, height: 30)
        context.fill(Path(ellipseIn: island), with: .color(IslandSwatch.sand))
        let rim = CGRect(x: island.minX + 8, y: island.minY + 2, width: 64, height: 10)
        context.opacity = 0.28
        context.fill(Path(ellipseIn: rim), with: .color(IslandSwatch.horizon))
        context.opacity = 1
    }
}

private extension AllClearIslandScene {
    static func drawPalm(in context: inout GraphicsContext, origin: CGPoint, sway: CGFloat) {
        let crown = CGPoint(x: origin.x + 10, y: origin.y - 54)
        var trunk = Path()
        trunk.move(to: CGPoint(x: origin.x - 3.5, y: origin.y))
        trunk.addQuadCurve(to: CGPoint(x: crown.x - 2, y: crown.y),
                           control: CGPoint(x: origin.x + 14, y: origin.y - 24))
        trunk.addLine(to: CGPoint(x: crown.x + 3, y: crown.y + 1))
        trunk.addQuadCurve(to: CGPoint(x: origin.x + 4, y: origin.y),
                           control: CGPoint(x: origin.x + 18, y: origin.y - 22))
        trunk.closeSubpath()
        context.fill(trunk, with: .color(IslandSwatch.trunk))
        drawTuft(in: &context, at: origin)
        context.drawLayer { fronds in
            fronds.translateBy(x: crown.x, y: crown.y)
            fronds.rotate(by: .radians(Double(sway)))
            fronds.translateBy(x: -crown.x, y: -crown.y)
            let angles: [CGFloat] = [-2.55, -2.10, -1.62, -1.18, -0.72, -0.28]
            let lengths: [CGFloat] = [26, 32, 30, 34, 28, 22]
            for (angle, length) in zip(angles, lengths) {
                fronds.fill(leaf(from: crown, length: length, angle: angle, width: length * 0.20),
                            with: .color(IslandSwatch.palm))
            }
        }
    }

    static func drawTuft(in context: inout GraphicsContext, at origin: CGPoint) {
        context.fill(leaf(from: origin, length: 8, angle: -2.2, width: 2.4), with: .color(IslandSwatch.palm))
        context.fill(leaf(from: origin, length: 7, angle: -1.4, width: 2.2), with: .color(IslandSwatch.palm))
        let pebble = Path(ellipseIn: CGRect(x: origin.x + 6, y: origin.y - 2, width: 5, height: 3.5))
        context.opacity = 0.35
        context.fill(pebble, with: .color(IslandSwatch.ink))
        context.fill(Path(ellipseIn: CGRect(x: origin.x + 11, y: origin.y - 1, width: 4, height: 3)),
                     with: .color(IslandSwatch.ink))
        context.opacity = 1
    }

    static func drawLounge(in context: inout GraphicsContext, origin: CGPoint) {
        context.drawLayer { local in
            local.translateBy(x: origin.x, y: origin.y)
            local.rotate(by: .degrees(-20))
            local.fill(Path(roundedRect: CGRect(x: -16, y: -8, width: 6, height: 28), cornerRadius: 2),
                       with: .color(IslandSwatch.trunk))
            local.fill(Path(roundedRect: CGRect(x: -16, y: 12, width: 38, height: 6), cornerRadius: 2),
                       with: .color(IslandSwatch.ink))
            local.fill(Path(roundedRect: CGRect(x: -16, y: 12, width: 38, height: 2.5), cornerRadius: 1.2),
                       with: .color(IslandSwatch.trunk))
            local.fill(Path(roundedRect: CGRect(x: -14, y: 18, width: 2.5, height: 8), cornerRadius: 1),
                       with: .color(IslandSwatch.trunk))
            local.fill(Path(roundedRect: CGRect(x: 16, y: 18, width: 2.5, height: 8), cornerRadius: 1),
                       with: .color(IslandSwatch.trunk))
            drawBoss(in: &local)
        }
    }

    static func drawBoss(in context: inout GraphicsContext) {
        context.fill(Path(ellipseIn: CGRect(x: -9, y: -32, width: 16, height: 11)),
                     with: .color(IslandSwatch.hair))
        context.fill(Path(ellipseIn: CGRect(x: -8, y: -30, width: 15, height: 15)),
                     with: .color(IslandSwatch.skin))
        context.fill(Path(roundedRect: CGRect(x: -6, y: -24, width: 5.5, height: 3.4), cornerRadius: 1.2),
                     with: .color(IslandSwatch.ink))
        context.fill(Path(roundedRect: CGRect(x: 1, y: -24, width: 5.5, height: 3.4), cornerRadius: 1.2),
                     with: .color(IslandSwatch.ink))
        context.fill(Path(roundedRect: CGRect(x: -1, y: -23, width: 3, height: 1.2), cornerRadius: 0.4),
                     with: .color(IslandSwatch.ink))
        context.fill(Path(roundedRect: CGRect(x: -10, y: -14, width: 20, height: 16), cornerRadius: 5),
                     with: .color(IslandSwatch.shirt))
        context.fill(Path(roundedRect: CGRect(x: -9, y: 0, width: 17, height: 11), cornerRadius: 3.5),
                     with: .color(IslandSwatch.ink))
        context.fill(Path(roundedRect: CGRect(x: 5, y: 5, width: 16, height: 5), cornerRadius: 2.5),
                     with: .color(IslandSwatch.ink))
        context.fill(Path(ellipseIn: CGRect(x: 18, y: 7, width: 5, height: 3)),
                     with: .color(IslandSwatch.skin))
        context.fill(Path(roundedRect: CGRect(x: -14, y: -28, width: 5, height: 12), cornerRadius: 2.5),
                     with: .color(IslandSwatch.skin))
        context.fill(Path(roundedRect: CGRect(x: 6, y: -28, width: 5, height: 12), cornerRadius: 2.5),
                     with: .color(IslandSwatch.skin))
    }

    static func drawLaptop(in context: inout GraphicsContext, origin: CGPoint) {
        let lid = CGRect(x: origin.x, y: origin.y, width: 18, height: 11)
        context.fill(Path(roundedRect: lid, cornerRadius: 2), with: .color(IslandSwatch.ink))
        context.opacity = 0.35
        context.fill(Path(roundedRect: CGRect(x: lid.minX + 2, y: lid.minY + 2, width: 14, height: 7), cornerRadius: 1),
                     with: .color(IslandSwatch.shimmer))
        context.opacity = 1
        context.fill(Path(roundedRect: CGRect(x: lid.minX - 1, y: lid.maxY - 2, width: 20, height: 3), cornerRadius: 1),
                     with: .color(IslandSwatch.ink))
    }
}
