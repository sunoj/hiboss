// Rendered avatar fallback, successful image, fixed square clipping and named color contrast coverage.
// Exports ProjectAvatarTests; depends on SwiftUI ImageRenderer, UIKit and HibossKit.

import HibossKit
import SwiftUI
import XCTest
@testable import HiBoss

@MainActor
final class ProjectAvatarTests: XCTestCase {
    func testLoadingAndFailureRenderTheSameProjectPlaceholder() throws {
        let placeholder = ProjectAvatarPlaceholder(slug: "hiboss", displayName: "HiBoss")
        let loading = try rendered(placeholder, phase: .empty)
        let failure = try rendered(placeholder, phase: .failure(URLError(.cannotConnectToHost)))
        XCTAssertEqual(loading, failure)
        let renamed = try rendered(ProjectAvatarPlaceholder(slug: "hiboss", displayName: "Other"),
                                   phase: .empty)
        XCTAssertNotEqual(loading, renamed, "the fallback renders the project's initial")
    }

    func testSuccessfulImageReplacesTheFallback() throws {
        let placeholder = ProjectAvatarPlaceholder(slug: "hiboss")
        let image = Image(uiImage: try XCTUnwrap(UIImage(systemName: "star.fill")))
        XCTAssertNotEqual(try rendered(placeholder, phase: .success(image)),
                          try rendered(placeholder, phase: .empty))
    }

    func testMissingAvatarRendersThePlaceholder() throws {
        let project = ProjectIdentity(id: "hiboss", slug: "hiboss", displayName: "HiBoss")
        let avatar = ImageRenderer(content: ProjectAvatarView(project: project, size: 44))
        let image = try XCTUnwrap(avatar.uiImage?.pngData())
        XCTAssertEqual(image, try rendered(project.placeholder, phase: .empty))
    }

    func testPlaceholderAndUploadedImageUseTheSameContinuousSquareAtEverySize() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40)).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
        }
        for size: CGFloat in [20, 44, 80] {
            let expected = try alphaMask(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(.black).frame(width: size, height: size))
            for slug in ["hiboss", "house", "smart-router", "ai-dispatch"] {
                for phase in [AsyncImagePhase.empty, .success(Image(uiImage: image))] {
                    let content = ProjectAvatarContent(placeholder: ProjectAvatarPlaceholder(slug: slug),
                        phase: phase).frame(width: size, height: size)
                    let actual = try alphaMask(content)
                    XCTAssertEqual(actual.count, expected.count)
                    XCTAssertEqual(zip(actual, expected).filter { abs(Int($0) - Int($1)) > 2 }.count,
                                   0, "\(slug), \(size)")
                }
            }
        }
    }

    func testAgentAndProgressInitialsAreCircular() throws {
        let agent = try alphaMask(AgentAvatarView(name: "Build Agent", size: 20))
        let circle = try alphaMask(Circle().fill(Theme.surface2).frame(width: 20, height: 20))
        XCTAssertEqual(Array(agent.prefix(80)), Array(circle.prefix(80)))
        XCTAssertEqual(agent.map { $0 > 0 }, circle.map { $0 > 0 })
        let expected = try alphaMask(Circle().fill(.black).frame(width: 20, height: 20))
        let chip = ProgressAttributionChip(agentLabel: nil, model: "claude-sonnet")
        XCTAssertEqual(try alphaMask(chip.frame(width: 20, height: 20, alignment: .leading).clipped()),
                       expected)
        XCTAssertEqual(HistoryMessage.avatarInitials(agentName: "Build Agent"), "Ba")
        XCTAssertEqual(HistoryMessage.avatarInitials(agentName: nil), "Ag")
    }

    func testNamedTintsKeepWhiteInitialsReadableInBothAppearances() throws {
        for name in ["Sky", "Lagoon", "Sand", "Palm", "Coral", "Violet", "Slate", "Amber"] {
            let color = try XCTUnwrap(UIColor(named: "Avatar\(name)"))
            for style in [UIUserInterfaceStyle.light, .dark] {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                XCTAssertTrue(color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
                    .getRed(&r, green: &g, blue: &b, alpha: &a))
                let luminance = zip([r, g, b], [0.2126, 0.7152, 0.0722]).reduce(0.0) { result, pair in
                    let value = Double(pair.0)
                    return result + (value <= 0.04045 ? value / 12.92
                        : pow((value + 0.055) / 1.055, 2.4)) * pair.1
                }
                XCTAssertGreaterThanOrEqual(1.05 / (luminance + 0.05), 4.5, name)
            }
        }
    }

    private func rendered(_ placeholder: ProjectAvatarPlaceholder, phase: AsyncImagePhase) throws -> Data {
        let renderer = ImageRenderer(content: ProjectAvatarContent(placeholder: placeholder, phase: phase)
            .frame(width: 44, height: 44))
        return try XCTUnwrap(renderer.uiImage?.pngData())
    }

}
