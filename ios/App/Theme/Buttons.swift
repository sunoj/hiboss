// Shared button styles: one shape and one height for every full-width action and decision option.
// Exports: HBButtonStyle (primary/secondary) and View.hbButton(_:alignment:).
// Dependencies: SwiftUI, Theme colours, Layout scale.

import SwiftUI

/// A full-width action or decision option: rounded rectangle, ≥ 48 pt tall, wraps freely.
/// Primary is the filled ink action. Every other option is bordered, so one screen has one
/// filled button. Never a capsule: a capsule around two lines of text reads as a blob.
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
            .foregroundStyle(label)
            .background(fill(pressed: configuration.isPressed), in: shape)
            .overlay { shape.strokeBorder(border, lineWidth: showsBorder ? 1 : 0) }
            .contentShape(shape)
            .opacity(configuration.isPressed && role == .primary ? 0.7 : 1)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
    }

    /// A disabled button drops its fill, not its legibility: the label keeps readable contrast
    /// while another option is submitting (`ProminentActionAppearanceTests` checks > 3:1).
    private func fill(pressed: Bool) -> Color {
        if role == .primary && isEnabled { return Theme.primaryAction }
        if !isEnabled || pressed { return Theme.surface2 }
        return .clear
    }

    private var showsBorder: Bool { role == .secondary && isEnabled }
    private var border: Color { showsBorder ? Theme.ink3 : .clear }
    private var label: Color {
        guard isEnabled else { return Theme.ink2 }
        return role == .primary ? Theme.onAccent : Theme.ink
    }
}

extension View {
    /// Applies the shared full-width button style.
    func hbButton(_ role: HBButtonStyle.Role, alignment: HorizontalAlignment = .leading) -> some View {
        buttonStyle(HBButtonStyle(role: role, alignment: alignment))
    }
}
