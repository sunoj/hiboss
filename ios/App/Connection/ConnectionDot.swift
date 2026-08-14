// Toolbar connection status: calm when healthy, loud only when failed.
// Exports: ConnectionDot used on Inbox, Sessions, Messages, and Settings.
// Dependencies: SwiftUI, HibossKit ConnectionState.

import HibossKit
import SwiftUI

struct ConnectionDot: View {
    let state: ConnectionState

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(tint)
            .symbolRenderingMode(.hierarchical)
            .symbolEffect(.pulse, isActive: pulsing)
            .accessibilityLabel("Connection: \(state.label)")
    }

    private var symbol: String {
        switch state {
        case .connected: "wifi"
        case .connecting: "wifi"
        case .failed: "wifi.exclamationmark"
        case .disconnected: "wifi.slash"
        }
    }

    /// Green only when live; every other state is the same quiet grey, so the
    /// glyph alone carries the status and nothing on the bar competes for attention.
    private var tint: Color {
        if case .connected = state { return .green }
        return Color(.tertiaryLabel)
    }

    private var pulsing: Bool {
        if case .connecting = state { return true }
        return false
    }
}
