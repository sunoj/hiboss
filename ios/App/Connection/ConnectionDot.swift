// Toolbar connection status: calm when healthy, loud only when failed.
// Exports: ConnectionDot used on Inbox, Sessions, Messages, and Settings.
// Dependencies: SwiftUI, HibossKit ConnectionState.

import HibossKit
import SwiftUI

struct ConnectionDot: View {
    let state: ConnectionState

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.pulse, isActive: pulsing)
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(captionColor)
            }
        }
        .accessibilityElement(children: .combine)
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

    private var tint: Color {
        switch state {
        case .connected: Color(.tertiaryLabel)
        case .connecting: Color(.secondaryLabel)
        case .failed: .red
        case .disconnected: Color(.tertiaryLabel)
        }
    }

    private var pulsing: Bool {
        if case .connecting = state { return true }
        return false
    }

    /// Healthy is icon-only; connecting and failed keep a short word.
    private var caption: String? {
        switch state {
        case .connected: nil
        case .connecting: "Connecting"
        case .failed: "Failed"
        case .disconnected: nil
        }
    }

    private var captionColor: Color {
        if case .failed = state { return .red }
        return .secondary
    }
}
