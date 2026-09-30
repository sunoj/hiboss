// Toolbar connection status: silent when connected, a small localized label otherwise.
// Exports: ConnectionDot used on the Messages, Sessions and session transcript toolbars.
// Dependencies: SwiftUI, HibossKit ConnectionState.

import HibossKit
import SwiftUI

struct ConnectionDot: View {
    let state: ConnectionState

    var body: some View {
        switch state {
        case .connected:
            EmptyView()
        case .connecting:
            Text("Connecting…")
                .font(.caption)
                .foregroundStyle(Theme.ink2)
                .accessibilityLabel(Text("Connection: \(state.label)"))
        case .disconnected, .failed:
            Label("Offline", systemImage: "wifi.slash")
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(tint)
                .accessibilityLabel(Text("Connection: \(state.label)"))
        }
    }

    /// Failure is the one state worth a warning tint; a plain disconnect stays quiet.
    private var tint: Color {
        if case .failed = state { return Theme.warn }
        return Theme.ink2
    }
}
