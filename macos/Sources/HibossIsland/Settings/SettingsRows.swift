// Reusable controls for the native Settings panes.
// Exports: pane headers, rows, status cards, toggles, and footer status.
// Dependencies: SwiftUI and DesignTokens.

import HibossKit
import SwiftUI

struct SettingsPaneBody<Content: View>: View {
    let pane: SettingsPane
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsPaneHeader(pane: pane)
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(DesignTokens.Colors.paper)
    }
}

struct SettingsPaneHeader: View {
    let pane: SettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(pane.title)
                .font(DesignTokens.Fonts.paneTitle)
                .foregroundStyle(DesignTokens.Colors.ink)
            Text(pane.subtitle)
                .font(DesignTokens.Fonts.body)
                .foregroundStyle(DesignTokens.Colors.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(DesignTokens.Fonts.monoLabel)
                .tracking(0.7)
                .foregroundStyle(DesignTokens.Colors.ink3)
            VStack(spacing: 0) {
                content
            }
            .background(DesignTokens.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.row))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.row)
                    .stroke(DesignTokens.Colors.line, lineWidth: 1)
            }
        }
    }
}

struct SettingsRow<Control: View>: View {
    let title: String
    let caption: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(DesignTokens.Fonts.rowTitle)
                    .foregroundStyle(DesignTokens.Colors.ink)
                Text(caption)
                    .font(DesignTokens.Fonts.caption)
                    .foregroundStyle(DesignTokens.Colors.ink3)
            }
            Spacer(minLength: 18)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Colors.line)
                .frame(height: 1)
                .padding(.leading, 14)
        }
    }
}

struct LastSettingsRow<Control: View>: View {
    let title: String
    let caption: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(DesignTokens.Fonts.rowTitle)
                    .foregroundStyle(DesignTokens.Colors.ink)
                Text(caption)
                    .font(DesignTokens.Fonts.caption)
                    .foregroundStyle(DesignTokens.Colors.ink3)
            }
            Spacer(minLength: 18)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct PulsingStatusDot: View {
    let isActive: Bool
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(isActive ? DesignTokens.Colors.live : DesignTokens.Colors.ink4)
            .frame(width: 8, height: 8)
            .overlay {
                Circle()
                    .stroke(isActive ? DesignTokens.Colors.live : .clear, lineWidth: 1)
                    .scaleEffect(pulse ? 2.2 : 1)
                    .opacity(pulse ? 0 : 0.55)
            }
            .onAppear { pulse = true }
            .animation(
                isActive ? .easeOut(duration: 1.4).repeatForever(autoreverses: false) : .default,
                value: pulse
            )
    }
}

struct SettingsFooterStatus: View {
    let text: String
    let isActive: Bool
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                PulsingStatusDot(isActive: isActive)
                Text(text.uppercased())
                    .font(DesignTokens.Fonts.monoLabel)
                    .tracking(0.7)
                    .foregroundStyle(DesignTokens.Colors.ink3)
            }
            if let error {
                Text(error)
                    .font(DesignTokens.Fonts.caption)
                    .foregroundStyle(DesignTokens.Colors.neg)
                    .lineLimit(2)
            }
        }
    }
}

struct RoutingToggle: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(isOn ? DesignTokens.Colors.pos.opacity(0.55) : .clear)
                .frame(width: 20, height: 20)
                .overlay {
                    Circle()
                        .stroke(isOn ? DesignTokens.Colors.live : DesignTokens.Colors.line2, lineWidth: 1)
                }
                .overlay {
                    Circle()
                        .fill(isOn ? DesignTokens.Colors.liveInner : .clear)
                        .frame(width: 7, height: 7)
                }
        }
        .buttonStyle(.plain)
    }
}

extension MessagePriority {
    var settingsLabel: String { rawValue }

    var settingsColor: Color {
        switch self {
        case .critical: DesignTokens.Colors.critical
        case .high: DesignTokens.Colors.high
        case .normal: DesignTokens.Colors.normal
        case .low: DesignTokens.Colors.low
        }
    }
}

extension NotificationChannel {
    var settingsLabel: String {
        switch self {
        case .discord: "Discord"
        case .telegram: "Telegram"
        case .api: "API"
        }
    }
}
