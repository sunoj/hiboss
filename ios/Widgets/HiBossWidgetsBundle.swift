// Widget bundle entry point for the HiBoss extension.
// Exports: HiBossWidgetsBundle (@main) hosting the decision Live Activity.
// Dependencies: WidgetKit, SwiftUI.

import SwiftUI
import WidgetKit

@main
struct HiBossWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DecisionLiveActivity()
    }
}
