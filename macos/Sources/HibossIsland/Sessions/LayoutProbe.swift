// Places an invisible AppKit anchor behind named views when a test installs a recorder.
// Exports: LayoutProbe and View.layoutProbe(_:); without a recorder nothing is added.
// Dependencies: SwiftUI and AppKit; anchors give exact window coordinates across split columns.

import AppKit
import SwiftUI

@MainActor
final class LayoutProbe {
    var anchors: [String: NSView] = [:]
}

extension EnvironmentValues {
    @Entry var layoutProbe: LayoutProbe?
}

extension View {
    func layoutProbe(_ id: String) -> some View {
        modifier(LayoutProbeModifier(id: id))
    }
}

private struct LayoutProbeModifier: ViewModifier {
    let id: String
    @Environment(\.layoutProbe) private var probe

    func body(content: Content) -> some View {
        content.background {
            if let probe { LayoutProbeAnchor(id: id, probe: probe) }
        }
    }
}

private struct LayoutProbeAnchor: NSViewRepresentable {
    let id: String
    let probe: LayoutProbe

    func makeNSView(context: Context) -> AnchorView {
        AnchorView(id: id, probe: probe)
    }

    func updateNSView(_ view: AnchorView, context: Context) {}

    /// SwiftUI also builds off-window copies while measuring; only an attached anchor counts.
    final class AnchorView: NSView {
        let id: String
        let probe: LayoutProbe

        init(id: String, probe: LayoutProbe) {
            self.id = id
            self.probe = probe
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { probe.anchors[id] = self }
        }
    }
}
