// Screenshot coverage for every shared decision-image consumer and progress media state.
// Exports IntermediateMediaUITests with held image, poster, video and like operations.
// Dependencies: IntermediateCaptureCase and bundled demo decisions.

import XCTest

final class IntermediateMediaUITests: IntermediateCaptureCase {
    func testOptionImageConsumers() {
        let states: [(String, [String: String])] = [
            ("home", [:]),
            ("detail", ["HIBOSS_DEMO_OPEN": "media-decision"]),
            ("transcript", ["HIBOSS_DEMO_SESSION": "1"]),
            ("resolved", ["HIBOSS_DEMO_RESOLVED": "1", "HIBOSS_DEMO_OPTION_MEDIA": "resolved"]),
            (
                "settled-detail",
                ["HIBOSS_DEMO_OPEN": "media-decision", "HIBOSS_DEMO_OPTION_MEDIA": "automatic"]
            ),
        ]
        for (name, route) in states {
            var extra = ["HIBOSS_DEMO_OPTION_MEDIA": "pending", "HIBOSS_DEMO_MEDIA_DELAY_MS": "60000"]
            extra.merge(route) { _, new in new }
            launch(extra)
            let image = app.buttons[
                variant.contains("zh") ? "打开「Coastal view」的图片" : "Open image for Coastal view"]
            reveal(image.firstMatch)
            holdAndCapture("image-\(name)")
            if name == "home" {
                image.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.1)).tap()
                holdAndCapture("image-zoom")
            }
        }
    }

    func testProgressImagesAndLikes() {
        launch(["HIBOSS_TAB": "progress", "HIBOSS_DEMO_MEDIA_DELAY_MS": "60000"])
        holdAndCapture("image-progress")
        let image = app.descendants(matching: .any)["wide landscape screenshot"].firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 8))
        image.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.8)).tap()
        holdAndCapture("image-progress-viewer")
        launch(["HIBOSS_TAB": "progress", "HIBOSS_DEMO_LIKE_DELAY_MS": "60000"])
        let like = app.buttons[variant.contains("zh") ? "喜欢" : "Like"].firstMatch
        XCTAssertTrue(like.waitForExistence(timeout: 8))
        for _ in 0..<6 where !like.isHittable { app.swipeUp() }
        like.tap()
        holdAndCapture("progress-like")
    }

    func testVideoAndPagination() {
        launch(["HIBOSS_TAB": "progress", "HIBOSS_DEMO_VIDEO_DELAY_MS": "60000"])
        let video = app.descendants(matching: .any)["progress-video"].firstMatch
        for _ in 0..<12 where !video.isHittable { app.swipeUp() }
        XCTAssertTrue(video.isHittable)
        holdAndCapture("video-progress")
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.3)).tap()
        holdAndCapture("video-viewer")
        launch(["HIBOSS_TAB": "progress", "HIBOSS_DEMO_PROGRESS_MORE_DELAY_MS": "60000"])
        app.swipeUp()
        holdAndCapture("progress-more")
        launch(["HIBOSS_DEMO_SESSION": "1", "HIBOSS_DEMO_TRANSCRIPT_EARLIER_DELAY_MS": "60000"])
        app.swipeDown()
        holdAndCapture("transcript-earlier")
    }
}
