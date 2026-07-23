// Reusable card + row building blocks shared across the Settings sections.
// Exports: SettingsSection, SettingsRow, SettingsDivider.
// Dependencies: SwiftUI, theme tokens.

import SwiftUI

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).hbLabel().foregroundStyle(Theme.ink4).padding(.leading, 6)
            VStack(spacing: 0) { content }
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
        }
    }
}

struct SettingsRow: View {
    let label: String
    var value: String = ""
    var valueColor: Color = Theme.ink2

    var body: some View {
        HStack {
            Text(label).font(.hbBody).foregroundStyle(Theme.ink)
            Spacer()
            if !value.isEmpty {
                Text(value).font(.hbCallout).foregroundStyle(valueColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 14)
    }
}
