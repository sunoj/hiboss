// Chinese light-mode refresh evidence for the two native notification preference screens.
// Exports StableSettingsRenderTests; reads are held while cached forms remain mounted.
// Dependencies: XCTest, SwiftUI, UIKit, PreferencesStore, and a controlled preference service.

import HibossKit
import SwiftUI
import UIKit
import XCTest
@testable import HiBoss

@MainActor
final class StableSettingsRenderTests: XCTestCase {
    func testNotificationFormsRetainTheirSectionGeometryDuringReadRecovery() async throws {
        let api = HeldSettingsRead()
        let store = PreferencesStore()
        await store.load(api: api)
        let push = PushStatusStore()
        let screens: [(String, AnyView)] = [
            ("notifications", AnyView(SettingsNotificationsView(store: store, push: push, api: nil,
                                                               onDecisionAlertsChanged: { _ in }))),
            ("delivery", AnyView(SettingsDeliveryView(store: store, api: nil))),
        ]
        for (name, screen) in screens {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = try XCTUnwrap(scenes.first)
            let window = UIWindow(windowScene: scene)
            window.frame = scene.coordinateSpace.bounds
            window.overrideUserInterfaceStyle = .light
            window.rootViewController = UIHostingController(rootView: NavigationStack { screen }
                .environment(\.locale, Locale(identifier: "zh-Hans")))
            window.isHidden = false
            await render()
            capture(window, name: name + "-settled")
            let baseline = window.rootViewController?.view.safeAreaInsets
            api.hold = true
            let refresh = Task { await store.load(api: api) }
            while api.pending == nil { await Task.yield() }
            await render()
            capture(window, name: name + "-mid-refresh")
            XCTAssertEqual(window.rootViewController?.view.safeAreaInsets, baseline)
            XCTAssertEqual(store.state, .loaded)
            XCTAssertTrue(store.hasLoaded)
            api.pending?.resume()
            api.pending = nil
            api.hold = false
            await refresh.value
            window.isHidden = true
        }
    }

    private func render() async {
        let done = expectation(description: "native form frame")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        await fulfillment(of: [done], timeout: 2)
    }

    private func capture(_ window: UIWindow, name: String) {
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "zh-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
private final class HeldSettingsRead: BossPreferencesServing {
    var hold = false
    var pending: CheckedContinuation<Void, Never>?

    func fetchPreferences() async throws -> BossPreferences {
        if hold { await withCheckedContinuation { pending = $0 } }
        return BossPreferences()
    }

    func updatePreferences(_ preferences: BossPreferences) async throws -> BossPreferences { preferences }
}
