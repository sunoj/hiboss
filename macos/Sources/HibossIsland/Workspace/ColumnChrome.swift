// The split divider is the only column edge. The titlebar does not paint a second one.
// Exports: ColumnChrome and columnChrome().
// Dependencies: AppKit and SwiftUI.

import AppKit
import SwiftUI

extension View {
    /// Hides the system titlebar fill so the split's own backgrounds meet at the divider.
    func columnChrome() -> some View {
        toolbarBackground(.hidden, for: .windowToolbar)
            .background(ColumnChrome())
    }
}

struct ColumnChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> ColumnChromeView { ColumnChromeView() }
    func updateNSView(_ view: ColumnChromeView, context: Context) { view.schedule() }
}

final class ColumnChromeView: NSView {
    private var scheduled = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        schedule()
    }

    override func layout() {
        super.layout()
        schedule()
    }

    func schedule() {
        guard !scheduled, window != nil else { return }
        scheduled = true
        Task { @MainActor in
            self.scheduled = false
            self.apply()
        }
    }

    func apply() {
        guard let window else { return }
        if window.titlebarSeparatorStyle != .none {
            window.titlebarSeparatorStyle = .none
        }
        if !window.titlebarAppearsTransparent {
            window.titlebarAppearsTransparent = true
        }
        solidLabels(in: window)
    }

    /// A transparent titlebar draws its labels with vibrancy, which washes them out.
    private func solidLabels(in window: NSWindow) {
        guard var root = window.contentView else { return }
        while let parent = root.superview { root = parent }
        let match = window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        let name: NSAppearance.Name = match == .darkAqua ? .darkAqua : .aqua
        guard let appearance = NSAppearance(named: name) else { return }
        for child in root.subviews where child.bounds.height > 20 && child.bounds.height < 120 {
            if child.appearance?.name != name { child.appearance = appearance }
        }
    }
}
