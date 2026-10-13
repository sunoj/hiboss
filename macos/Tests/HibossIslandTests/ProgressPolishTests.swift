// Regressions for sidebar identity matching, stable media geometry and decoded cache reuse.
// Exports: ProgressPolishTests; exercises production loaders against loopback HTTP fixtures.
// Dependencies: AppKit, SwiftUI, HibossKit, XCTest and HistorySnapshotMediaServer.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class ProgressPolishTests: XCTestCase {
    func testPostIdentityMatchesSidebarSlugOrNameIgnoringCase() {
        let avatar = URL(string: "https://example.com/house.png")
        let identity = ProjectIdentity(id: "canonical", slug: "house-slug", displayName: "House",
            avatarURL: avatar)
        let session = ProjectSession(id: "session", projectId: identity.id, projectSlug: identity.slug,
            branch: "main", projectRef: identity)
        for name in ["HOUSE", "HOUSE-SLUG"] {
            let fallback = ProjectIdentity(id: name, slug: name, displayName: name)
            XCTAssertEqual(ProgressProjectIdentity.resolve(fallback, sessions: [session]), identity)
        }
        let unrelated = ProjectIdentity(id: "other", slug: "other", displayName: "Other")
        XCTAssertEqual(ProgressProjectIdentity.resolve(unrelated, sessions: [session]), unrelated)
    }

    func testIdentityPrefersAvatarAcrossMultipleSessionsAndPreservesPostAvatar() {
        let placeholder = ProjectSession(id: "old", projectId: "house", projectSlug: "house", branch: nil)
        let identity = ProjectIdentity(id: "house", slug: "house", displayName: "House",
            avatarURL: URL(string: "https://example.com/house.png"))
        let current = ProjectSession(id: "new", projectId: "house", projectSlug: "house", branch: nil,
            projectRef: identity)
        XCTAssertEqual(ProgressProjectIdentity.resolve(identity, sessions: [placeholder]), identity)
        XCTAssertEqual(ProgressProjectIdentity.resolve(placeholder.avatarProject,
            sessions: [placeholder, current]), identity)
    }

    func testMediaReservesDeclaredAspectRatioAndCapsColumnsAndHeight() {
        let square = media(width: 400, height: 400)
        let wide = media(width: 800, height: 400)
        let frames = ProgressMediaLayout(items: [square, square, wide]).frames(width: 408)
        XCTAssertEqual(frames, [CGRect(x: 0, y: 0, width: 200, height: 200),
            CGRect(x: 208, y: 0, width: 200, height: 200),
            CGRect(x: 0, y: 208, width: 200, height: 100)])
        XCTAssertEqual(ProgressMediaLayout(items: [square]).frames(width: 900).first?.height, 240)
        XCTAssertEqual(ProgressMediaLayout.aspectRatio(media(width: 0, height: nil)), 16 / 9)
        XCTAssertEqual(ProgressMediaLayout.aspectRatio(media(width: 400, height: 800)), 0.5)
    }

    func testSecondCachedViewHasItsImageOnFirstFrameAndMakesZeroRequests() async throws {
        let server = HistorySnapshotMediaServer()
        try await server.start()
        defer { server.stop() }
        let path = "/ship.png?progress=\(UUID().uuidString)"
        let address = server.baseURL + path
        let original = ProgressImageLoader(url: address)
        await original.load(address)
        let image = try XCTUnwrap(original.image)
        let rebuilt = ProgressImageLoader(url: address)
        XCTAssertTrue(rebuilt.image === image, "The first frame must synchronously use the cache")
        await rebuilt.load(address)
        let view = NSHostingView(rootView: ProgressRemoteImage(url: address, alt: "Fixture"))
        view.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(server.requestedPaths, [path], "A second cached view must make zero requests")
    }

    func testRenderedGridReservesDeclaredDimensionsBeforeImagesLoad() throws {
        for (width, height, expected) in [(400, 400, 200), (800, 400, 100)] {
            let items = [media(width: width, height: height),
                ProgressMedia(url: "https://example.com/second.png", kind: .image,
                    contentType: "image/png", size: 0, width: width, height: height)]
            let renderer = ImageRenderer(content: ProgressMediaGrid(items: items, onOpen: { _ in }))
            renderer.proposedSize = ProposedViewSize(width: 408, height: nil)
            XCTAssertEqual(try XCTUnwrap(renderer.nsImage).size.height, CGFloat(expected))
        }
    }

    func testFailuresAreNotCachedAndChangedURLsDoNotRetainOldImages() async throws {
        let server = HistorySnapshotMediaServer()
        try await server.start()
        defer { server.stop() }
        let loader = ProgressImageLoader(url: server.baseURL + "/ship.png")
        await loader.load(server.baseURL + "/ship.png")
        XCTAssertNotNil(loader.image)
        for path in ["/missing.png", "/port"] {
            let address = server.baseURL + path
            await loader.load(address)
            XCTAssertNil(loader.image)
            XCTAssertTrue(loader.failed)
            let rebuilt = ProgressImageLoader(url: address)
            XCTAssertNil(rebuilt.image)
            await rebuilt.load(address)
            XCTAssertEqual(server.requestedPaths.filter { $0 == path }.count, 2)
        }
    }

    private func media(width: Int?, height: Int?) -> ProgressMedia {
        ProgressMedia(url: "https://example.com/image.png", kind: .image, contentType: "image/png",
            size: 0, width: width, height: height)
    }
}
