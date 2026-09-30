// Shared iOS prominent-button styling with an explicit contrasting label color.
// Exports: ProminentActionModifier; macOS keeps its native button rendering.
// Dependencies: SwiftUI.

#if os(iOS)
import SwiftUI

public struct ProminentActionModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    private let labelColor: Color

    public init(labelColor: Color) {
        self.labelColor = labelColor
    }

    public func body(content: Content) -> some View {
        content
            .buttonStyle(.borderedProminent)
            .foregroundStyle(isEnabled ? labelColor : Color(uiColor: .label))
    }
}
#endif
