// Tests for opening the main window by scene id from the status menu and notifications.
// Covers: opener installation, repeated close/reopen requests, early requests, and routing.
// Dependencies: XCTest, AppKit, HibossKit MessageID, and MessageNotificationNavigation.

import AppKit
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class MainWindowNavigationTests: XCTestCase {
    /// Stands in for the single `Window` scene: opening shows it, closing hides it.
    @MainActor private final class SceneWindow {
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 200, height: 120),
            styleMask: [.titled, .closable], backing: .buffered, defer: true)
        var opens = 0

        init(title: String) {
            window.isReleasedWhenClosed = false
            window.title = title
        }

        func open() {
            opens += 1
            window.orderFront(nil)
        }
    }

    func testOpenMainWindowUsesSceneOpenerWhateverTheWindowTitle() {
        var activations = 0
        let navigation = MessageNotificationNavigation(activate: { activations += 1 })
        let scene = SceneWindow(title: L("Needs You"))
        navigation.install(scene.open)

        navigation.openMainWindow()

        XCTAssertNotEqual(scene.window.title, productName)
        XCTAssertTrue(scene.window.isVisible)
        XCTAssertEqual(scene.opens, 1)
        XCTAssertEqual(activations, 1)
    }

    func testRepeatedCloseAndReopenRequestsEachReachTheOpener() {
        let navigation = MessageNotificationNavigation(activate: {})
        let scene = SceneWindow(title: L("Dashboard"))
        navigation.install(scene.open)

        for cycle in 1...3 {
            scene.window.close()
            XCTAssertFalse(scene.window.isVisible)
            navigation.openMainWindow()
            XCTAssertTrue(scene.window.isVisible, "cycle \(cycle)")
        }
        XCTAssertEqual(scene.opens, 3)
    }

    func testRequestBeforeInstallationOpensOnceAfterInstallation() async {
        let navigation = MessageNotificationNavigation(activate: {})
        var opens = 0
        navigation.openMainWindow()
        navigation.install { opens += 1 }
        XCTAssertEqual(opens, 0, "replayed asynchronously, not during command evaluation")
        await settle()
        XCTAssertEqual(opens, 1)

        navigation.install { opens += 1 }
        await settle()
        XCTAssertEqual(opens, 1, "re-evaluated commands must not reopen the window")
    }

    func testNotificationOpenTargetsMessageAndOpensMainWindow() {
        let navigation = MessageNotificationNavigation(activate: {})
        var opens = 0
        navigation.install { opens += 1 }

        navigation.open(MessageID(rawValue: "msg-1"))
        navigation.open(MessageID(rawValue: "msg-2"))

        XCTAssertEqual(navigation.target?.id, MessageID(rawValue: "msg-2"))
        XCTAssertEqual(opens, 2)
    }

    func testNotificationBeforeInstallationKeepsTargetAndOpensOnce() async {
        let navigation = MessageNotificationNavigation(activate: {})
        var opens = 0
        navigation.open(MessageID(rawValue: "early"))
        navigation.install { opens += 1 }
        await settle()

        XCTAssertEqual(navigation.target?.id, MessageID(rawValue: "early"))
        XCTAssertEqual(opens, 1)
    }

    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }
}
