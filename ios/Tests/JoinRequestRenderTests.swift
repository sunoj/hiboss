// Renders the iOS approval sheet and Device Requests list offscreen in both appearances.
// Exports: JoinRequestRenderTests; set TEST_RUNNER_HIBOSS_JOIN_SNAPSHOTS=<dir> to keep PNGs.
// Dependencies: XCTest, SwiftUI, UIKit, HibossKit join requests, and the HiBoss app target.

import HibossKit
import SwiftUI
import UIKit
import XCTest
@testable import HiBoss

@MainActor
final class JoinRequestRenderTests: XCTestCase {
    func testSheetAndListRenderInBothAppearances() async throws {
        let request = JoinRequest(
            id: "jr-1", deviceLabel: "mini", deviceHost: "mini.local", inviterLabel: "Office Mac",
            verificationCode: "012345",
            profiles: [JoinRequestProfile(profile: "claude", name: "mini-claude"),
                       JoinRequestProfile(profile: "codex", name: "mini-codex")]
        )
        let model = JoinRequestsModel { RenderService(requests: [request]) }
        await model.refresh()
        let views: [(String, AnyView)] = [
            ("sheet", AnyView(NavigationStack { JoinRequestReviewView(requestID: "jr-1", model: model) })),
            ("list", AnyView(NavigationStack { DeviceRequestsView(model: model) })),
        ]
        for (name, view) in views {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let image = try await render(view, style: style)
                XCTAssertGreaterThan(image.size.height, 600)
                write(image, name: "\(name)-\(style == .light ? "light" : "dark")")
            }
        }
    }

    private func render(_ view: AnyView, style: UIUserInterfaceStyle) async throws -> UIImage {
        // A window draws only when attached to the host app's scene.
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.overrideUserInterfaceStyle = style
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(500))
        window.layoutIfNeeded()
        return UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    private func write(_ image: UIImage, name: String) {
        guard let directory = ProcessInfo.processInfo.environment["HIBOSS_JOIN_SNAPSHOTS"],
              let png = image.pngData() else { return }
        try? png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("ios-join-\(name).png"))
    }
}

private struct RenderService: JoinRequestServing {
    let requests: [JoinRequest]
    func listPendingJoinRequests() async throws -> [JoinRequest] { requests }
    func approveJoinRequest(id: String) async throws -> JoinApproval { throw JoinRequestError.notFound }
    func rejectJoinRequest(id: String) async throws { throw JoinRequestError.notFound }
}
