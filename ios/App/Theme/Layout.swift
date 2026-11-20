// Layout scale: spacing, corner radii, avatar sizes and the shared card/section treatments.
// Exports: Space, Radius, AvatarSize, ReadableWidth and shared View treatments.
// Dependencies: SwiftUI, Theme colours, Typography.

import SwiftUI

/// The only spacing values views use, for padding and stack spacing alike.
/// A value off this scale is a design decision and belongs here first, named.
enum Space {
    /// Hairline gaps inside one compound element (title ↔ its subtitle).
    static let xxs: CGFloat = 4
    /// Between items that belong together (icon ↔ label, chip ↔ chip, option ↔ option).
    static let xs: CGFloat = 8
    /// Between blocks inside one card or row.
    static let s: CGFloat = 12
    /// Card and row inner padding; the screen's side margin.
    static let m: CGFloat = 16
    /// Between cards in a stack.
    static let l: CGFloat = 20
    /// Between a section's header and the previous section.
    static let xl: CGFloat = 24
    /// Empty-state and onboarding breathing room.
    static let xxl: CGFloat = 32
}

/// Corner radii. Capsules are for chips, badges and single-line system actions, never for
/// buttons that can wrap.
enum Radius {
    /// Thumbnails, tags, small media.
    static let small: CGFloat = 8
    /// Buttons, text fields, option rows, inline media.
    static let medium: CGFloat = 12
    /// Cards and grouped surfaces.
    static let large: CGFloat = 16
}

/// Avatar and leading-tile sizes.
enum AvatarSize {
    /// Beside caption or footnote text (agent chips, meta lines).
    static let inline: CGFloat = 20
    /// Beside a headline or a card's meta line.
    static let compact: CGFloat = 28
    /// The leading tile of a list row or feed post.
    static let row: CGFloat = 40
}

/// The minimum interactive size, and the height of full-width controls.
enum ControlMetric {
    static let minTap: CGFloat = 44
    static let fullWidth: CGFloat = 48
}

enum ReadableWidth {
    static let maximum: CGFloat = 640
}

struct HBReadableWidth: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: ReadableWidth.maximum)
            .frame(maxWidth: .infinity)
            .background(Theme.paper)
    }
}

/// A grouped card: surface fill, large radius, standard inner padding.
struct HBCard: ViewModifier {
    var padding: CGFloat = Space.m

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
    }
}

/// Grouped-list section header: footnote, secondary, so it does not compete with the
/// navigation title. Callers align it with the card's content edge.
struct HBSectionHeader: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.hbFootnote)
            .foregroundStyle(Theme.ink2)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    func hbReadableWidth() -> some View { modifier(HBReadableWidth()) }
    func hbCard(padding: CGFloat = Space.m) -> some View { modifier(HBCard(padding: padding)) }
    func hbSectionHeader() -> some View { modifier(HBSectionHeader()) }
}
