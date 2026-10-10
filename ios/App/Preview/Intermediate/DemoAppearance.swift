// Deterministic appearance for demo screenshots without changing device preferences.
// Exports DemoAppearance, read only by the demo app root.
// Dependencies: SwiftUI and the AppleInterfaceStyle launch argument.

import SwiftUI

enum DemoAppearance {
    static var colorScheme: ColorScheme? {
        switch UserDefaults.standard.string(forKey: "AppleInterfaceStyle") {
        case "Light": .light
        case "Dark": .dark
        default: nil
        }
    }
}
