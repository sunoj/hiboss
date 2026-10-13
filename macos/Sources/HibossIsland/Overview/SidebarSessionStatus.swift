// Renders independent attention/unread indicators and the live-work caption.
// Exports: SidebarSessionIndicator and SidebarWorkingCaption with accessible localized labels.
// Dependencies: SwiftUI, TodayStyle, and native semantic unread colour.

import SwiftUI

enum SidebarSessionIndicator: Equatable {
    case needsYou, unread, none

    init(needsYou: Bool, unread: Bool) {
        self = needsYou ? .needsYou : unread ? .unread : .none
    }

    var label: String {
        switch self {
        case .needsYou: L("Needs You")
        case .unread: L("Unread")
        case .none: ""
        }
    }

    @MainActor func view(sessionID: String) -> some View {
        ZStack {
            if self != .none {
                Circle().fill(self == .needsYou ? TodayStyle.signal : Color(nsColor: .systemBlue))
                    .accessibilityLabel(label)
                    .layoutProbe("sidebar.\(self == .needsYou ? "needsYou" : "unread").\(sessionID)")
            }
        }
        .frame(width: 7, height: 7)
        .accessibilityHidden(self == .none)
    }
}

struct SidebarWorkingCaption: View {
    @Environment(\.backgroundProminence) private var prominence

    /// Green on a plain row; an emphasized selected row keeps the selection's own foreground.
    static func usesStatusColor(_ prominence: BackgroundProminence) -> Bool {
        prominence != .increased
    }

    var body: some View {
        Text(L("Working"))
            .font(.caption).foregroundStyle(Self.usesStatusColor(prominence)
                ? AnyShapeStyle(TodayStyle.settled) : AnyShapeStyle(.secondary))
            .fixedSize().layoutPriority(1)
            .accessibilityLabel(L("Working now"))
    }
}
