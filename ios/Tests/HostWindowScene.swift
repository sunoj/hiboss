// The host app's window scene for tests that put a SwiftUI view in a real UIWindow.
// Exports: hostWindowScene(), which waits for the scene a cold simulator connects late.
// Dependencies: UIKit and XCTest.

import UIKit
import XCTest

/// A freshly booted simulator can start the tests before the host app connects its scene.
@MainActor
func hostWindowScene(timeout: Duration = .seconds(30)) async throws -> UIWindowScene {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            return scene
        }
        try await Task.sleep(for: .milliseconds(100))
    }
    return try XCTUnwrap(nil as UIWindowScene?, "The host app never connected a window scene")
}
