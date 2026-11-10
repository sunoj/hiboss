// Inline, full-width choice rows for Select (radio) and MultiSelect (checkbox) on both platforms.
// Exports PanelOption, panelOptions(_:) and PanelChoiceList; labels wrap and never clip.
// Dependencies: SwiftUI and the shared panel element/value types.

import SwiftUI

struct PanelOption: Identifiable, Equatable {
    let id: String
    let label: String
    let description: String?
}

func panelOptions(_ element: PanelElement) -> [PanelOption] {
    element.props["options"]?.array?.compactMap { option -> PanelOption? in
        guard let object = option.object, let id = object["id"]?.string, let label = object["label"]?.string
        else { return nil }
        return PanelOption(id: id, label: label, description: object["description"]?.string)
    } ?? []
}

enum PanelChoiceStyle { case single, multiple }

/// The question as a headline, an optional hint, then one tappable row per option.
struct PanelChoiceList: View {
    let label: String
    let path: String
    let hint: String?
    let options: [PanelOption]
    let style: PanelChoiceStyle
    let isSelected: (String) -> Bool
    let select: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: label).font(.headline).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let hint { Text(verbatim: hint).font(.callout).foregroundStyle(.secondary) }
            VStack(spacing: 6) {
                ForEach(options) { option in
                    PanelChoiceRow(option: option, style: style, selected: isSelected(option.id)) { select(option.id) }
                        .accessibilityIdentifier("panel-option-\(path)-\(option.id)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

private struct PanelChoiceRow: View {
    let option: PanelOption
    let style: PanelChoiceStyle
    let selected: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: indicator)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .font(.body)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: option.label).font(.body).foregroundStyle(.primary)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    if let description = option.description {
                        Text(verbatim: description).font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(isEnabled ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: [option.label, option.description].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var indicator: String {
        switch style {
        case .single: return selected ? "largecircle.fill.circle" : "circle"
        case .multiple: return selected ? "checkmark.square.fill" : "square"
        }
    }

    private var background: Color { selected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.06) }
}
