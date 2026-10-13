// Observes the key state of the actual window hosting a session workspace.
// Exports: SessionWindowKeyReader, used by MainView to gate live read acknowledgements.
// Dependencies: AppKit and SwiftUI; never observes another window as this workspace.

import AppKit
import SwiftUI

struct SessionWindowKeyReader: NSViewRepresentable {
    @Binding var isKey: Bool

    func makeNSView(context: Context) -> KeyView {
        KeyView { isKey = $0 }
    }

    func updateNSView(_ view: KeyView, context: Context) {}

    final class KeyView: NSView {
        private let changed: (Bool) -> Void

        init(changed: @escaping (Bool) -> Void) {
            self.changed = changed
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            if let window {
                for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                    NotificationCenter.default.addObserver(self, selector: #selector(keyChanged),
                        name: name, object: window)
                }
            }
            publish()
        }

        @objc private func keyChanged(_ notification: Notification) { publish() }

        private func publish() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.changed(self.window?.isKeyWindow == true)
            }
        }
    }
}
