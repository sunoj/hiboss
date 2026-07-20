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
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct SettingsPaneHeader: View {
    let pane: SettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(pane.title)
                .font(Font.title3.weight(.semibold))
                .foregroundStyle(Color.primary)
            Text(pane.subtitle)
                .font(Font.body)
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// States plainly that a pane's settings are stored but not yet acted on.
/// These preferences persist to the server, but nothing consults them at delivery time
/// yet — showing the controls without saying so would make them read as working switches.
struct SettingsNotAppliedNotice: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.orange)
            Text("Saved, but not applied yet. Delivery still follows each agent's channel "
                 + "configuration; these preferences take effect in a later release.")
                .font(Font.caption)
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.tile))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.tile)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(Font.caption.monospaced())
                .tracking(0.7)
                .foregroundStyle(Color.secondary)
            VStack(spacing: 0) {
                content
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.notice))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.notice)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
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
                    .font(Font.headline)
                    .foregroundStyle(Color.primary)
                Text(caption)
                    .font(Font.caption)
                    .foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 18)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
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
                    .font(Font.headline)
                    .foregroundStyle(Color.primary)
                Text(caption)
                    .font(Font.caption)
                    .foregroundStyle(Color.secondary)
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
            .fill(isActive ? DesignTokens.live : Color(nsColor: .tertiaryLabelColor))
            .frame(width: 8, height: 8)
            .overlay {
                Circle()
                    .stroke(isActive ? DesignTokens.live : .clear, lineWidth: 1)
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
                    .font(Font.caption.monospaced())
                    .tracking(0.7)
                    .foregroundStyle(Color.secondary)
            }
            if let error {
                Text(error)
                    .font(Font.caption)
                    .foregroundStyle(Color.red)
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
                .fill(isOn ? DesignTokens.live.opacity(0.55) : .clear)
                .frame(width: 20, height: 20)
                .overlay {
                    Circle()
                        .stroke(isOn ? DesignTokens.live : Color(nsColor: .separatorColor), lineWidth: 1)
                }
                .overlay {
                    Circle()
                        .fill(isOn ? DesignTokens.live : .clear)
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
        case .critical: DesignTokens.Priority.critical
        case .high: DesignTokens.Priority.high
        case .normal: DesignTokens.Priority.normal
        case .low: DesignTokens.Priority.low
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
