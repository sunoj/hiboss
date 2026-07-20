// SwiftUI row for one message in the macOS History window.
// Exports: HistoryRow with v2 row layout and state styling.
// Dependencies: SwiftUI, HibossKit HistoryMessage, and design tokens.

import HibossKit
import SwiftUI

struct HistoryRow: View {
    let message: HistoryMessage

    var body: some View {
        HStack(spacing: 0) {
            unreadAccent
            rowBody
        }
        .background(message.isUnreadHistoryMessage ? DesignTokens.Colors.surface2 : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                .strokeBorder(DesignTokens.Colors.line, lineWidth: 1)
        )
    }

    private var unreadAccent: some View {
        Rectangle()
            .fill(message.isUnreadHistoryMessage ? priorityColor : Color.clear)
            .frame(width: 3)
    }

    private var rowBody: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 7) {
                header
                Text(message.body)
                    .font(.system(size: 13))
                    .foregroundStyle(message.isUnreadHistoryMessage ? DesignTokens.Colors.ink : DesignTokens.Colors.ink2)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
                footer
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
    }

    private var avatar: some View {
        Text(message.historyMonogram)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(DesignTokens.Colors.ink)
            .frame(width: 30, height: 30)
            .background(avatarBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.pill, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.pill, style: .continuous)
                    .strokeBorder(DesignTokens.Colors.line2, lineWidth: 1)
            )
    }

    @ViewBuilder
    private var avatarBackground: some View {
        if message.isBossHistoryMessage {
            LinearGradient(
                colors: [DesignTokens.Colors.pos, DesignTokens.Colors.warn],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            DesignTokens.Colors.avatarTile
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(message.historyDisplayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.ink)
            Image(systemName: message.historyDirectionGlyph)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.ink3)
            Text(message.historyPriorityModeLabel)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(DesignTokens.Colors.ink3)
            Spacer(minLength: 8)
            Text(message.historyTimestamp)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.ink4)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(message.historyStatusChip)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
                        .strokeBorder(DesignTokens.Colors.line2, lineWidth: 1)
                )
            Spacer(minLength: 0)
        }
    }

    private var priorityColor: Color {
        switch message.priority.lowercased() {
        case "critical": DesignTokens.Colors.critical
        case "high": DesignTokens.Colors.high
        case "low": DesignTokens.Colors.low
        default: DesignTokens.Colors.normal
        }
    }

    private var statusColor: Color {
        switch message.status.lowercased() {
        case "replied": DesignTokens.Colors.pos
        case "delivered": DesignTokens.Colors.warn
        case "expired": DesignTokens.Colors.ink4
        default: DesignTokens.Colors.ink3
        }
    }
}
