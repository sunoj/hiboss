// The width rule for a two-column Today and Sessions: list on the left, the selected item's detail beside it.
// Exports: ColumnLayout, TwoColumnSplit, RouteSelection, RouteLink and View.measuresListColumnWidth(_:).
// Dependencies: SwiftUI; RootTabView measures the window and passes the list width down.

import SwiftUI

enum ColumnLayout {
    /// The narrowest window, in points, that shows two columns: an unfolded Duo in landscape (951)
    /// and an iPad mini in landscape (1133) qualify; every portrait iPhone and iPad mini do not.
    static let twoColumnMinWidth: CGFloat = 900
    static let maxListWidth: CGFloat = 420

    /// The list column's width, or nil when the window shows one column.
    static func listWidth(forAvailableWidth width: CGFloat) -> CGFloat? {
        guard width >= twoColumnMinWidth else { return nil }
        return min(maxListWidth, (width * 0.4).rounded())
    }
}

/// The list at a fixed width with a detail column beside it; with no width, only the list, unchanged.
/// The list keeps its place in the hierarchy either way, so rotating keeps its state.
struct TwoColumnSplit<List: View, Detail: View>: View {
    let listWidth: CGFloat?
    @ViewBuilder let list: List
    @ViewBuilder let detail: Detail

    var body: some View {
        HStack(spacing: 0) {
            list.frame(width: listWidth)
            if listWidth != nil {
                Divider().ignoresSafeArea()
                detail
            }
        }
    }
}

/// Set on a two-column list: rows select into the detail column instead of pushing.
struct RouteSelection {
    var selected: AnyHashable?
    var select: (any Hashable) -> Void
}

private struct RouteSelectionKey: EnvironmentKey {
    static var defaultValue: RouteSelection? { nil }
}

extension EnvironmentValues {
    var routeSelection: RouteSelection? {
        get { self[RouteSelectionKey.self] }
        set { self[RouteSelectionKey.self] = newValue }
    }
}

/// A list row that pushes its value, or selects it when the list sits beside a detail column.
struct RouteLink<Value: Hashable, Label: View>: View {
    let value: Value
    @ViewBuilder let label: Label
    @Environment(\.routeSelection) private var selection

    var body: some View {
        if let selection {
            Button { selection.select(value) } label: {
                label.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(selection.selected == AnyHashable(value) ? Theme.surface2 : nil)
            .accessibilityAddTraits(selection.selected == AnyHashable(value) ? .isSelected : [])
        } else {
            NavigationLink(value: value) { label }
        }
    }
}

extension View {
    /// Reports the list column width for this window: its full width, safe-area insets included.
    func measuresListColumnWidth(_ width: Binding<CGFloat?>) -> some View {
        onGeometryChange(for: CGFloat?.self) { proxy in
            let insets = proxy.safeAreaInsets
            return ColumnLayout.listWidth(forAvailableWidth: proxy.size.width + insets.leading + insets.trailing)
        } action: { width.wrappedValue = $0 }
    }
}
