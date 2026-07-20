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
        .background(message.isUnreadHistoryMessage ? DesignTokens.surface2 : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                .strokeBorder(DesignTokens.line, lineWidth: 1)
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
                    .foregroundStyle(message.isUnreadHistoryMessage ? DesignTokens.ink : DesignTokens.ink2)
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
            .foregroundStyle(DesignTokens.ink)
            .frame(width: 30, height: 30)
            .background(avatarBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.segment, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.segment, style: .continuous)
                    .strokeBorder(DesignTokens.line2, lineWidth: 1)
            )
    }

    @ViewBuilder
    private var avatarBackground: some View {
        if message.isBossHistoryMessage {
            LinearGradient(
                colors: [DesignTokens.pos, DesignTokens.warn],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            DesignTokens.avatarTile
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(message.historyDisplayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.ink)
            Image(systemName: message.historyDirectionGlyph)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignTokens.ink3)
            Text(message.historyPriorityModeLabel)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(DesignTokens.ink3)
            Spacer(minLength: 8)
            Text(message.historyTimestamp)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(DesignTokens.ink4)
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
                        .strokeBorder(DesignTokens.line2, lineWidth: 1)
                )
            Spacer(minLength: 0)
        }
    }

    private var priorityColor: Color {
        switch message.priority.lowercased() {
        case "critical": DesignTokens.Priority.critical
        case "high": DesignTokens.Priority.high
        case "low": DesignTokens.Priority.low
        default: DesignTokens.Priority.normal
        }
    }

    private var statusColor: Color {
        switch message.status.lowercased() {
        case "replied": DesignTokens.pos
        case "delivered": DesignTokens.warn
        case "expired": DesignTokens.ink4
        default: DesignTokens.ink3
        }
    }
}
