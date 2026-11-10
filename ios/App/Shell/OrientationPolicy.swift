// Which orientations the app supports: landscape only on a wide iPhone screen (an unfolded Duo).
// Exports: OrientationPolicy, View.refreshesSupportedOrientations().
// Dependencies: SwiftUI, UIKit; consulted by AppDelegate.

import SwiftUI
import UIKit

enum OrientationPolicy {
    /// The shortest side, in points, at which an iPhone screen may turn to landscape.
    static let landscapeShortSide: CGFloat = 600

    /// iPad keeps every orientation; an iPhone rotates only when its screen is wide.
    static func mask(shortSide: CGFloat, idiom: UIUserInterfaceIdiom) -> UIInterfaceOrientationMask {
        guard idiom == .phone else { return .all }
        return shortSide >= landscapeShortSide ? .allButUpsideDown : .portrait
    }

    @MainActor
    static func mask(for scene: UIWindowScene?) -> UIInterfaceOrientationMask {
        let bounds = scene?.coordinateSpace.bounds ?? .zero
        return mask(shortSide: min(bounds.width, bounds.height), idiom: UIDevice.current.userInterfaceIdiom)
    }

    /// Asks UIKit to re-read the mask, and turns back to portrait when landscape is no longer allowed.
    @MainActor
    static func refresh() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            if mask(for: scene) == .portrait, scene.interfaceOrientation.isLandscape {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
        }
    }
}

extension View {
    /// Re-evaluates the supported orientations whenever the window's short side changes (fold/unfold).
    func refreshesSupportedOrientations() -> some View {
        onGeometryChange(for: CGFloat.self) { proxy in
            let insets = proxy.safeAreaInsets
            return min(proxy.size.width + insets.leading + insets.trailing,
                       proxy.size.height + insets.top + insets.bottom)
        } action: { _ in
            OrientationPolicy.refresh()
        }
    }
}
