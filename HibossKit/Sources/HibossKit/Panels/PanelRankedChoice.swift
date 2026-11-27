// Catalog v2 RankedChoice: numbered rows the boss reorders with move buttons (and VoiceOver adjust).
// Exports: PanelRankedChoice and RankedChoiceOrder (the pure order/answer rules).
// Dependencies: SwiftUI, PanelOption, and the PanelStore value binding.

import SwiftUI

/// The order shown and the answer written: the stored ids when they are a valid ranking, else the
/// options' own order. The answer is the first `topK` ids.
enum RankedChoiceOrder {
    static func order(stored: [String]?, options: [PanelOption]) -> [String] {
        let ids = options.map(\.id)
        guard let stored, !stored.isEmpty, Set(stored).isSubset(of: ids), Set(stored).count == stored.count
        else { return ids }
        return stored + ids.filter { !stored.contains($0) }
    }

    static func moved(_ order: [String], from index: Int, by offset: Int) -> [String] {
        let target = index + offset
        guard order.indices.contains(index), order.indices.contains(target) else { return order }
        var result = order
        result.swapAt(index, target)
        return result
    }

    static func answer(_ order: [String], topK: Int?) -> [String] {
        Array(order.prefix(topK ?? order.count))
    }
}

struct PanelRankedChoice: View {
    let label: String
    let options: [PanelOption]
    let topK: Int?
    @Binding var value: PanelValue

    private var stored: [String]? { value.array?.compactMap(\.string) }
    private var order: [String] { RankedChoiceOrder.order(stored: stored, options: options) }
    private var ranked: Int { topK ?? options.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: label).font(.headline).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 6) {
                ForEach(Array(order.enumerated()), id: \.element) { index, id in
                    if index == ranked { Divider().overlay(Text(kitL("Not ranked")).font(.caption)
                        .foregroundStyle(.secondary).padding(.horizontal, 6).background(.background)) }
                    row(index: index, option: options.first { $0.id == id })
                }
            }
            if stored == nil {
                Button(kitL("Keep this order")) { write(order) }
                    .font(.callout)
                    .accessibilityIdentifier("panel-ranked-keep")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func row(index: Int, option: PanelOption?) -> some View {
        if let option {
            HStack(alignment: .center, spacing: 10) {
                Text(verbatim: index < ranked ? "\(index + 1)" : "–")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(index < ranked ? 0.08 : 0.03), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: option.label).fixedSize(horizontal: false, vertical: true)
                    if let description = option.description {
                        Text(verbatim: description).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                moveButton("chevron.up", kitL("Move up"), enabled: index > 0) { move(index, by: -1) }
                moveButton("chevron.down", kitL("Move down"), enabled: index < order.count - 1) { move(index, by: 1) }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(index < ranked ? kitL("Rank \(index + 1): \(option.label)") : option.label)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: move(index, by: -1)
                case .decrement: move(index, by: 1)
                @unknown default: break
                }
            }
            .accessibilityIdentifier("panel-ranked-\(option.id)")
        }
    }

    private func moveButton(_ symbol: String, _ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.callout.weight(.semibold))
                .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.4))
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(enabled ? 0.07 : 0.03), in: Circle())
                .contentShape(Circle())
        }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .help(title)
            .accessibilityLabel(title)
    }

    private func move(_ index: Int, by offset: Int) {
        write(RankedChoiceOrder.moved(order, from: index, by: offset))
    }

    /// Stores only the ranked prefix, which is the answer; the unranked tail follows the options' order.
    private func write(_ order: [String]) {
        value = .array(RankedChoiceOrder.answer(order, topK: topK).map(PanelValue.string))
    }
}
