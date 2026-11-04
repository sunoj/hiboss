// Shared button styles: one shape and one height for every full-width action and decision option.
// Exports: HBButtonStyle (primary/secondary) and View.hbButton(_:alignment:).
// Dependencies: SwiftUI, Theme colours, Layout scale.

import SwiftUI

/// A full-width action or decision option: rounded rectangle, ≥ 48 pt tall, wraps freely.
/// Primary is the filled ink action (the first option, the screen's main action); secondary is
/// a quiet fill that reads on both the grouped ground and a card surface. Never a capsule:
/// a capsule around two lines of text reads as a blob.
struct HBButtonStyle: ButtonStyle {
    enum Role { case primary, secondary }

    let role: Role
    var alignment: HorizontalAlignment = .leading
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.hbBody)
            .multilineTextAlignment(alignment == .center ? .center : .leading)
            .frame(maxWidth: .infinity, minHeight: ControlMetric.fullWidth,
                   alignment: Alignment(horizontal: alignment, vertical: .center))
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.xs)
            .foregroundStyle(role == .primary ? Theme.onAccent : Theme.ink)
            .background(fill, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }

    private var fill: Color { role == .primary ? Theme.primaryAction : Theme.surface2 }
}

extension View {
    /// Applies the shared full-width button style.
    func hbButton(_ role: HBButtonStyle.Role, alignment: HorizontalAlignment = .leading) -> some View {
        buttonStyle(HBButtonStyle(role: role, alignment: alignment))
    }
}
