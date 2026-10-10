// Rendered avatar fallback, successful image, shapes and named color contrast coverage.
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

    func testAllShapesStayWithinTheAvatarBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
        for shape in ProjectAvatarPlaceholder.Shape.allCases {
            XCTAssertEqual(ProjectAvatarShape(kind: shape).path(in: bounds).boundingRect, bounds)
        }
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
