// Renders a ```copy fence as wrapped verbatim text with a labelled copy button.
// Exports MessagePasteboard; the button copies exactly the text shown, never a trimmed form.
// Dependencies: SwiftUI with the UIKit or AppKit general pasteboard.

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum MessagePasteboard {
    /// Replaceable so tests can observe the copied string without touching the system pasteboard.
    @MainActor public static var write: (String) -> Void = { text in
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

struct CopyableTextBlock: View {
    let label: String?
    let text: String
    @State private var copies = 0
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let label {
                    Text(verbatim: label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                copyButton
            }
            Text(verbatim: text).font(.callout.monospaced()).foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("message.copyable.text")
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.tint.opacity(0.4)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("message.copyable")
        .task(id: copies) {
            guard copies > 0 else { return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { copied = false }
        }
    }

    private var copyButton: some View {
        Button {
            Self.copy(text)
            copied = true
            copies += 1
        } label: {
            Label(copied ? kitL("Copied") : kitL("Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.caption.weight(.semibold))
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .sensoryFeedback(.success, trigger: copies)
        .accessibilityLabel(label.map { kitL("Copy \($0)") } ?? kitL("Copy"))
        .accessibilityValue(copied ? kitL("Copied") : "")
        .accessibilityIdentifier("message.copyable.copy")
    }

    @MainActor static func copy(_ text: String) { MessagePasteboard.write(text) }
}
