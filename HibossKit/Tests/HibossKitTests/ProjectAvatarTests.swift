// Covers the project avatar placeholder: stable, slug-driven, and spread across the palette.

import XCTest
@testable import HibossKit

final class ProjectAvatarTests: XCTestCase {
    func testSameSlugAlwaysGivesTheSamePlaceholder() {
        XCTAssertEqual(ProjectAvatarPlaceholder(slug: "smart-router"),
                       ProjectAvatarPlaceholder(slug: "Smart-Router"))
        // Pinned values: changing the hash would silently repaint every project.
        let pinned = ProjectAvatarPlaceholder(slug: "hiboss")
        XCTAssertEqual(ProjectAvatarPlaceholder.fnv1a("hiboss"), 0xe032_36ae_4025_9ca3)
        XCTAssertEqual(pinned, ProjectAvatarPlaceholder(slug: "hiboss"))
    }

    func testDisplayNameSetsTheInitialButNotColourOrShape() {
        let plain = ProjectAvatarPlaceholder(slug: "house")
        let named = ProjectAvatarPlaceholder(slug: "house", displayName: "Baan Mae Hia")
        XCTAssertEqual(plain.initial, "H")
        XCTAssertEqual(named.initial, "B")
        XCTAssertEqual(plain.tint, named.tint)
        XCTAssertEqual(plain.shape, named.shape)
    }

    func testInitialSkipsPunctuationAndHandlesEmpty() {
        XCTAssertEqual(ProjectAvatarPlaceholder(slug: "1inch-fusion-filler").initial, "1")
        XCTAssertEqual(ProjectAvatarPlaceholder(slug: "-x").initial, "X")
        XCTAssertEqual(ProjectAvatarPlaceholder(slug: "").initial, "?")
    }

    func testRealProjectsSpreadAcrossTintsAndShapes() {
        let slugs = ["hiboss", "house", "smart-router", "ai-dispatch", "revert-liquidator",
                     "open-intent-filler", "1inch-fusion-filler", "morpho-liquidator", "swap-mumaren"]
        let placeholders = slugs.map { ProjectAvatarPlaceholder(slug: $0) }
        XCTAssertGreaterThanOrEqual(Set(placeholders.map(\.tint)).count, 4)
        XCTAssertGreaterThanOrEqual(Set(placeholders.map(\.shape)).count, 3)
    }
}
