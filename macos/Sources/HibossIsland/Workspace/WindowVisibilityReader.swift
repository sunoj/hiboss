// Observes whether the window hosting a view is on screen (not minimized, hidden or covered).
// Exports: WindowVisibilityReader, which gates background reads to a visible surface.
// Dependencies: AppKit and SwiftUI; observes only the hosting window.

import AppKit
import SwiftUI

struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> VisibilityView {
        VisibilityView { isVisible = $0 }
    }

    func updateNSView(_ view: VisibilityView, context: Context) {}

    final class VisibilityView: NSView {
        private let changed: (Bool) -> Void
        private var published: Bool?

        init(changed: @escaping (Bool) -> Void) {
            self.changed = changed
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        deinit { NotificationCenter.default.removeObserver(self) }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            if let window {
                NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged),
                    name: NSWindow.didChangeOcclusionStateNotification, object: window)
            }
            publish()
        }

        @objc private func occlusionChanged(_ notification: Notification) { publish() }

        private func publish() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let visible = self.window?.occlusionState.contains(.visible) == true
                guard visible != self.published else { return }
                self.published = visible
                self.changed(visible)
            }
        }
    }
}
