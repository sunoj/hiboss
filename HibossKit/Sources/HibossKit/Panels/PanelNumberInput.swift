// Preserves partially typed decimals while storing typed questionnaire answers.
// Exports the native PanelNumberInput and the DisabledFieldText style shared by catalog fields.
// Dependencies: SwiftUI text editing and PanelStore; no locale-dependent coercion.

import SwiftUI

struct PanelNumberInput: View {
    let label: String
    let path: String
    @ObservedObject var store: PanelStore
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: label).font(.headline)
            TextField(label, text: Binding(get: { text }, set: {
                text = $0
                store.setText($0, at: path)
            }))
            .textFieldStyle(.roundedBorder).focused($focused).modifier(DisabledFieldText())
            .accessibilityLabel(label)
        }
        .onAppear { text = storedText }
        .onChange(of: storedText) { _, updated in if !focused { text = updated } }
        .onChange(of: focused) { _, active in if !active { text = storedText } }
    }

    private var storedText: String { panelValue(at: path, in: store.state)?.displayText ?? "" }
}

/// iOS keeps full-strength text in a disabled field; dim it to the secondary label, as macOS does.
struct DisabledFieldText: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        #if os(iOS)
        content.foregroundStyle(isEnabled ? Color.primary : Color.secondary)
        #else
        content
        #endif
    }
}
