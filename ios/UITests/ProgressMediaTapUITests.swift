// UI coverage for tapping progress-feed media into the full-screen viewer.
// Exports: ProgressMediaTapUITests.
// Dependencies: XCTest.

import XCTest

final class ProgressMediaTapUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.configureDemoLaunch(["HIBOSS_TAB": "progress"])
        app.launch()
        XCTAssertTrue(
            app.navigationBars["Progress"].waitForExistence(timeout: 10),
            "demo Progress tab should appear"
        )
    }

    func testTappingFeedImageOpensFullScreenViewer() {
        let image = app.images["wide landscape screenshot"].firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 8), "demo feed image should appear")
        image.tap()
        assertViewerOpened(after: "single-image accessibility tap")
    }

    func testViewerImageFillsScreenAndIsCentered() {
        openViewer(label: "wide landscape screenshot")
        assertViewerMediaFitted(label: "wide landscape screenshot")
        dismissViewer()

        openViewer(label: "tall portrait screenshot")
        assertViewerMediaFitted(label: "tall portrait screenshot")
    }

    func testTappingTwoItemMosaicOpensViewer() {
        continueAfterFailure = true
        assertCellOpensViewer("leading still", corner: CGVector(dx: 0.25, dy: 0.25))
        assertCellOpensViewer("trailing still", corner: CGVector(dx: 0.75, dy: 0.25))
    }

    func testTappingThreeItemMosaicOpensViewer() {
        continueAfterFailure = true
        assertCellOpensViewer("lead still", corner: CGVector(dx: 0.25, dy: 0.5))
        assertCellOpensViewer("top still", corner: CGVector(dx: 0.75, dy: 0.25))
        assertCellOpensViewer("bottom still", corner: CGVector(dx: 0.75, dy: 0.75))
    }

    func testTappingFourItemMosaicOpensViewer() {
        continueAfterFailure = true
        // Bottom-leading uses mid-left, not (0.2, 0.8): that corner is the ALT control.
        assertCellOpensViewer("quad top leading", corner: CGVector(dx: 0.25, dy: 0.25))
        assertCellOpensViewer("quad top trailing", corner: CGVector(dx: 0.75, dy: 0.25))
        assertCellOpensViewer("quad bottom leading", corner: CGVector(dx: 0.3, dy: 0.4))
        assertCellOpensViewer("quad bottom trailing", corner: CGVector(dx: 0.75, dy: 0.75))
    }

    func testTappingVideoFrameOpensViewer() {
        continueAfterFailure = true
        let speaker = reveal(app.buttons["speaker.slash.fill"].firstMatch)
        XCTAssertTrue(speaker.waitForExistence(timeout: 8), "demo video speaker control should appear")

        speaker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 90, dy: -80))
            .tap()
        assertViewerOpened(after: "video frame coordinate tap")
        dismissViewer()

        let clip = media("looping demo clip")
        XCTAssertTrue(clip.waitForExistence(timeout: 3), "video cell labeled 'looping demo clip' should appear")
        clip.tap()
        assertViewerOpened(after: "video accessibility tap")
    }
}

private extension ProgressMediaTapUITests {
    func assertCellOpensViewer(_ label: String, corner: CGVector) {
        let cell = reveal(media(label))
        XCTAssertTrue(cell.waitForExistence(timeout: 8), "\(label) should appear")

        cell.tap()
        assertViewerOpened(after: "\(label) accessibility tap")
        dismissViewer()

        let again = ensureFullyOnScreen(reveal(media(label)))
        let frame = again.frame
        again.coordinate(withNormalizedOffset: corner).tap()
        assertViewerOpened(
            after: "\(label) coordinate tap at \(corner.dx),\(corner.dy) cell=\(frame)"
        )
        dismissViewer()
    }

    func ensureFullyOnScreen(_ element: XCUIElement) -> XCUIElement {
        let window = app.windows.firstMatch.frame
        let bottom = window.maxY - 120
        let top = window.minY + 96
        for _ in 0..<8 {
            let frame = element.frame
            if frame.height > 0, frame.maxY < bottom, frame.minY > top { return element }
            if frame.maxY >= bottom {
                app.swipeUp(velocity: XCUIGestureVelocity(80))
            } else if frame.minY <= top {
                app.swipeDown(velocity: XCUIGestureVelocity(80))
            } else {
                return element
            }
        }
        return element
    }

    func media(_ label: String) -> XCUIElement {
        let image = app.images[label].firstMatch
        if image.exists { return image }
        let other = app.otherElements[label].firstMatch
        if other.exists { return other }
        return app.buttons[label].firstMatch.exists
            ? app.buttons[label].firstMatch
            : image
    }

    func reveal(_ element: XCUIElement) -> XCUIElement {
        if element.waitForExistence(timeout: 1), element.isHittable { return element }
        var seen = false
        for _ in 0..<12 {
            if element.exists {
                seen = true
                if element.isHittable { return element }
            }
            if seen, !element.exists {
                app.swipeDown(velocity: XCUIGestureVelocity(180))
            } else {
                app.swipeUp(velocity: XCUIGestureVelocity(180))
            }
        }
        _ = element.waitForExistence(timeout: 3)
        return element
    }

    func assertViewerOpened(after reason: String) {
        XCTAssertTrue(
            app.buttons["Close"].firstMatch.waitForExistence(timeout: 3),
            "full-screen viewer should present after \(reason)"
        )
    }

    func openViewer(label: String) {
        let cell = ensureFullyOnScreen(reveal(media(label)))
        XCTAssertTrue(cell.waitForExistence(timeout: 8), "\(label) should appear in feed")
        cell.tap()
        assertViewerOpened(after: "\(label) open for geometry")
    }

    /// Zoom host UIView must fill the scroll view, and the image sit near center —
    /// not a zero/corner UIKit frame (pre-fix ProgressZoomView failure mode).
    /// SwiftUI accessibility frames alone can look fine while the UIKit host is 0x0.
    func assertViewerMediaFitted(label: String) {
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.width, 0, "window should have a size")

        let scroll = app.scrollViews.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "progress-zoom-scroll")
        ).firstMatch
        XCTAssertTrue(
            scroll.waitForExistence(timeout: 5),
            "progress-zoom-scroll should exist"
        )

        var hostWidth: CGFloat = 0
        var hostHeight: CGFloat = 0
        var parsed = false
        var lastID = ""
        for _ in 0..<20 {
            lastID = scroll.identifier
            if let host = parseHostValue(fromIdentifier: lastID) {
                hostWidth = host.width
                hostHeight = host.height
                parsed = true
                if hostWidth > 1, hostHeight > 1 { break }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        XCTAssertTrue(parsed, "expected identifier containing host:WxH@X,Y, got \(lastID)")
        XCTAssertGreaterThan(
            hostWidth, window.width * 0.9,
            "zoom host width \(hostWidth) should track screen (\(window.width)); id=\(lastID)"
        )
        XCTAssertGreaterThan(
            hostHeight, window.height * 0.9,
            "zoom host height \(hostHeight) should track screen (\(window.height)); id=\(lastID)"
        )

        let query = app.images.matching(NSPredicate(format: "label == %@", label))
        XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 8), "\(label) in viewer")

        var best = CGRect.zero
        for i in 0..<query.count {
            let frame = query.element(boundBy: i).frame
            if frame.width * frame.height > best.width * best.height {
                best = frame
            }
        }

        XCTAssertGreaterThan(best.width, 40, "\(label) should be visible; frame=\(best)")
        XCTAssertEqual(
            best.midX, window.midX, accuracy: window.width * 0.12,
            "\(label) should be horizontally centred; frame=\(best) window=\(window)"
        )
        XCTAssertEqual(
            best.midY, window.midY, accuracy: window.height * 0.2,
            "\(label) should be vertically centred; frame=\(best) window=\(window)"
        )
    }

    func parseHostValue(fromIdentifier value: String) -> CGRect? {
        guard let range = value.range(of: "host:") else { return nil }
        let body = String(value[range.upperBound...])
        let atParts = body.split(separator: "@", maxSplits: 1).map(String.init)
        guard atParts.count == 2 else { return nil }
        let sizeParts = atParts[0].split(separator: "x").compactMap { Double($0) }
        let originParts = atParts[1].split(separator: ",").compactMap { Double($0) }
        guard sizeParts.count == 2, originParts.count == 2 else { return nil }
        return CGRect(
            x: originParts[0], y: originParts[1],
            width: sizeParts[0], height: sizeParts[1]
        )
    }

    func dismissViewer() {
        let close = app.buttons["Close"].firstMatch
        guard close.exists else { return }
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 2), "viewer should dismiss")
    }
}
