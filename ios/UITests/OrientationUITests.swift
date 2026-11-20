// Rotation checks for the root shell: a regular iPhone stays portrait, an iPad turns.
// Exports: OrientationUITests, with an "orientation-after-rotate" screenshot attachment.
// Dependencies: XCTest and DemoLaunchSupport.

import XCTest

@MainActor
final class OrientationUITests: XCTestCase {
    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testRotatingKeepsPhonePortraitAndTurnsPad() {
        let app = XCUIApplication()
        app.configureDemoLaunch()
        app.launchConfiguredDemo()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.appears(timeout: 10))

        XCUIDevice.shared.orientation = .landscapeLeft
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let settled = NSPredicate { _, _ in
            let frame = window.frame
            return isPad ? frame.width > frame.height : frame.width < frame.height
        }
        // A phone must still be portrait after the system had time to rotate.
        if !isPad { RunLoop.current.run(until: Date().addingTimeInterval(2)) }
        wait(for: [expectation(for: settled, evaluatedWith: window)], timeout: 5)
        captureDemoScreenshot(app, name: "orientation-after-rotate", test: self)
        app.terminate()
    }
}
