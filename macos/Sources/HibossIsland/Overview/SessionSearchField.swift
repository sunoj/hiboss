// Native sidebar search with AppKit focus, contrast, clearing, and accessibility.
// Exports: SessionSearchField, bridging NSSearchField to the SwiftUI search binding.
// Dependencies: AppKit and SwiftUI; search updates immediately as the user types.

import AppKit
import SwiftUI

struct SessionSearchField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderAttributedString = NSAttributedString(string: L("Find a session"),
            attributes: [.foregroundColor: NSColor.secondaryLabelColor])
        field.setAccessibilityLabel(L("Find a session"))
        field.setAccessibilityIdentifier("overview.sessionSearch")
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
