// Answer button and plain-text supporting copy for option surfaces.
// Exports: OptionButton and OptionDescriptionText, shared by resolved rows.
// Dependencies: SwiftUI and OptionRowMetrics.

import SwiftUI

struct OptionButton: View {
    let title: String
    var description: String? = nil
    var isDefault: Bool = false
    var isSending: Bool = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            label
            .foregroundStyle(.white)
            .padding(.horizontal, OptionRowMetrics.horizontalPadding)
            .padding(.vertical, OptionRowMetrics.verticalPadding)
            .frame(minHeight: OptionRowMetrics.minimumHeight)
            .background(Color.white.opacity(isHovering ? 0.16 : (isDefault ? 0.14 : 0.09)))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.white.opacity(isDefault ? 0.35 : 0), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .scaleEffect(isHovering ? 1.01 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .accessibilityLabel(isDefault ? L("Choose \(title), default") : L("Choose \(title)"))
    }

    private var label: some View {
        HStack(spacing: 7) {
            if isDefault {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .bold))
                    .opacity(0.9)
            }
            VStack(alignment: .leading, spacing: OptionRowMetrics.descriptionSpacing) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                OptionDescriptionText(text: description)
            }
            if isDefault {
                Text(L("default"))
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.white.opacity(0.18), in: Capsule())
                    .opacity(0.85)
            }
            Spacer()
            if isSending {
                ProgressView().controlSize(.small)
                Text(L("Sending…")).font(.caption)
            } else {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .opacity(isHovering ? 0.9 : 0.35)
            }
        }
    }
}

struct OptionDescriptionText: View {
    let text: String?

    var body: some View {
        if let text {
            Text(verbatim: text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
