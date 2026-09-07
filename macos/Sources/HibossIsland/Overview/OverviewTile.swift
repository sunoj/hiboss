// Native category button with the icon/count hierarchy from the Reminders reference.
// Exports: OverviewTile and category accents.
// Dependencies: SwiftUI, OverviewCategory, DesignTokens overview colors.

import SwiftUI

struct OverviewTile: View {
    let category: OverviewCategory
    let count: Int
    let isSelected: Bool
    let countsAvailable: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) { tileContent }
            .buttonStyle(.plain)
            .accessibilityLabel(category.title)
            .accessibilityValue(countsAvailable ? "\(count)" : L("Loading…"))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("overview.\(category.rawValue)")
    }

    private var tileContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: category.symbol).font(.title3.weight(.semibold))
                Spacer(minLength: 4)
                Text(countsAvailable ? "\(count)" : "—")
                    .font(.title2.bold()).monospacedDigit()
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(category.tileTitle)
                    .font(.headline).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected { Image(systemName: "checkmark.circle.fill").font(.caption) }
            }
            .frame(minHeight: 32, alignment: .bottomLeading)
        }
        .foregroundStyle(DesignTokens.Overview.ink)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background { glassSurface }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(isSelected ? 0.95 : 0), lineWidth: 2)
                .padding(3)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    private var glassSurface: some View {
        let shape = RoundedRectangle(cornerRadius: 14)
        return shape.fill(category.color)
            .overlay {
                shape.fill(LinearGradient(stops: [
                    .init(color: .white.opacity(0.50), location: 0),
                    .init(color: .white.opacity(0.12), location: 0.45),
                    .init(color: .clear, location: 1),
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.2)],
                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
            .shadow(color: category.color.opacity(0.18), radius: 5, y: 2)
    }
}

extension OverviewCategory {
    var tileTitle: String {
        switch self {
        case .waiting: L("Waiting")
        case .all: L("All")
        default: title
        }
    }

    var color: Color {
        switch self {
        case .needsYou: DesignTokens.Overview.needsYou
        case .automatic: DesignTokens.Overview.automatic
        case .waiting: DesignTokens.Overview.waiting
        case .urgent: DesignTokens.Overview.urgent
        case .all: DesignTokens.Overview.all
        case .completed: DesignTokens.Overview.completed
        }
    }
}
