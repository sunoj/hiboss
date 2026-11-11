// The width rule for a two-column Today and Sessions: list on the left, the selected item's detail beside it.
// Exports: ColumnLayout, TwoColumnSplit, RouteSelection, RouteLink, keepsTabBar,
// View.measuresListColumnWidth(_:), View.listColumnIgnoresRail(), View.measuresSideRail(_:).
// Dependencies: SwiftUI, UIKit; RootTabView measures the window and passes the list width down.

import SwiftUI
import UIKit

enum ColumnLayout {
    /// The narrowest window, in points, that shows two columns: an unfolded Duo in landscape (951)
    /// and an iPad mini in landscape (1133) qualify; every portrait iPhone and iPad mini do not.
    static let twoColumnMinWidth: CGFloat = 900
    static let maxListWidth: CGFloat = 420

    /// Demo-only `-HibossTwoColumnMinWidth <pt>` lowers the threshold so a folded Duo simulator, which
    /// draws the side rail, shows two columns; no simulator can unfold a Duo.
    static var minWidth: CGFloat {
        let override = isDemoMode ? UserDefaults.standard.double(forKey: "HibossTwoColumnMinWidth") : 0
        return override > 0 ? override : twoColumnMinWidth
    }

    /// The negative extra inset that brings a side inset a column received down to the part of the
    /// window's safe area its frame really overlaps; zero when it received no more than that.
    static func insetCorrection(received: CGFloat, overlap: CGFloat) -> CGFloat {
        min(0, max(0, overlap) - received)
    }

    /// True when a side rail (the Duo's) sits on one edge: the view is inset on that side only.
    /// A landscape iPhone insets both sides alike; a portrait iPhone and an iPad inset neither.
    static func drawsRail(leading: CGFloat, trailing: CGFloat) -> Bool {
        min(leading, trailing) == 0 && max(leading, trailing) > 0
    }

    /// The list column's width, or nil when the window shows one column.
    static func listWidth(forAvailableWidth width: CGFloat, minWidth: CGFloat = twoColumnMinWidth) -> CGFloat? {
        guard width >= minWidth else { return nil }
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

private struct KeepsTabBarKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

extension EnvironmentValues {
    var routeSelection: RouteSelection? {
        get { self[RouteSelectionKey.self] }
        set { self[RouteSelectionKey.self] = newValue }
    }

    /// True in a detail column beside a list: its screens keep the tabs instead of hiding them.
    var keepsTabBar: Bool {
        get { self[KeepsTabBarKey.self] }
        set { self[KeepsTabBarKey.self] = newValue }
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
    /// Set on the root inside the list column's NavigationStack. The system hands that root the
    /// window's side insets even where the column never reaches the window edge, so a side rail (the
    /// Duo's) would narrow the list content by the rail's width. A column that does reach the edge
    /// keeps its inset, so one column is unchanged. The navigation bar takes the rail inset on its
    /// own and is not corrected here.
    func listColumnIgnoresRail() -> some View {
        background(ColumnInsetCorrector().accessibilityHidden(true))
    }

    /// Reports whether this view sits beside a side rail, which then holds its toolbar items.
    func measuresSideRail(_ drawsRail: Binding<Bool>) -> some View {
        onGeometryChange(for: Bool.self) { proxy in
            ColumnLayout.drawsRail(leading: proxy.safeAreaInsets.leading, trailing: proxy.safeAreaInsets.trailing)
        } action: { drawsRail.wrappedValue = $0 }
    }

    /// Reports the list column width for this window: its full width, safe-area insets included.
    func measuresListColumnWidth(_ width: Binding<CGFloat?>) -> some View {
        onGeometryChange(for: CGFloat?.self) { proxy in
            let insets = proxy.safeAreaInsets
            return ColumnLayout.listWidth(forAvailableWidth: proxy.size.width + insets.leading + insets.trailing,
                                          minWidth: ColumnLayout.minWidth)
        } action: { width.wrappedValue = $0 }
    }
}

/// Trims the hosting controller's side insets to what its frame really overlaps of the window's
/// safe area, through `additionalSafeAreaInsets`, so only the column at the screen edge yields.
private struct ColumnInsetCorrector: UIViewRepresentable {
    /// Fills the root, so a size change (fold, unfold, rotation) lays it out again.
    func makeUIView(context: Context) -> CorrectorView {
        let view = CorrectorView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: CorrectorView, context: Context) { uiView.setNeedsLayout() }

    final class CorrectorView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let window, let controller = hostingController else { return }
            let frame = controller.view.convert(controller.view.bounds, to: window)
            let safe = window.safeAreaInsets
            var extra = controller.additionalSafeAreaInsets
            let inset = controller.view.safeAreaInsets
            let left = ColumnLayout.insetCorrection(received: inset.left - extra.left,
                                                    overlap: safe.left - frame.minX)
            let right = ColumnLayout.insetCorrection(received: inset.right - extra.right,
                                                     overlap: frame.maxX - (window.bounds.width - safe.right))
            guard extra.left != left || extra.right != right else { return }
            extra.left = left
            extra.right = right
            controller.additionalSafeAreaInsets = extra
        }

        private var hostingController: UIViewController? {
            var responder: UIResponder? = next
            while let current = responder, !(current is UIViewController) { responder = current.next }
            return responder as? UIViewController
        }
    }
}
