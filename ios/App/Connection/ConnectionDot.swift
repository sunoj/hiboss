// Toolbar connection status: silent when connected, a small localized label otherwise.
// Exports: ConnectionDot used on the Activity and session transcript toolbars; a narrow
// toolbar (the Duo's vertical rail) gets the icon alone. Dependencies: SwiftUI, HibossKit ConnectionState.

import HibossKit
import SwiftUI

struct ConnectionDot: View {
    let state: ConnectionState

    var body: some View {
        switch state {
        case .connected:
            EmptyView()
        case .connecting:
            ViewThatFits(in: .horizontal) {
                Text("Connecting…").font(.caption).fixedSize()
                ProgressView().controlSize(.small)
            }
            .foregroundStyle(Theme.ink2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Connection: \(state.label)"))
        case .disconnected, .failed:
            ViewThatFits(in: .horizontal) {
                Label("Offline", systemImage: "wifi.slash").labelStyle(.titleAndIcon).fixedSize()
                Image(systemName: "wifi.slash")
            }
            .font(.caption)
            .foregroundStyle(tint)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Connection: \(state.label)"))
        }
    }

    /// Failure is the one state worth a warning tint; a plain disconnect stays quiet.
    private var tint: Color {
        if case .failed = state { return Theme.warn }
        return Theme.ink2
    }
}
