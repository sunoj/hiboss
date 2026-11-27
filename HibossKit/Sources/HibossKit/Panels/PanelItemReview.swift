// Catalog v2 ItemReview: one verdict per item, a note where the verdict asks for one.
// Exports: PanelItemReview, ReviewVerdict, and ItemReviewAnswer (pure answer rules).
// Dependencies: SwiftUI, PanelOption, and the PanelStore value binding.

import SwiftUI

struct ReviewVerdict: Identifiable, Equatable {
    let id: String
    let label: String
    let requiresNote: Bool
}

func reviewVerdicts(_ element: PanelElement) -> [ReviewVerdict] {
    element.props["verdicts"]?.array?.compactMap { value -> ReviewVerdict? in
        guard let object = value.object, let id = object["id"]?.string, let label = object["label"]?.string
        else { return nil }
        return ReviewVerdict(id: id, label: label, requiresNote: object["requiresNote"]?.bool ?? false)
    } ?? []
}

/// Reads and edits the `{itemID: {verdict, note?}}` answer object.
enum ItemReviewAnswer {
    static func verdict(_ value: PanelValue, item: String) -> String? {
        value.object?[item]?.object?["verdict"]?.string
    }

    static func note(_ value: PanelValue, item: String) -> String {
        value.object?[item]?.object?["note"]?.string ?? ""
    }

    static func setting(_ value: PanelValue, item: String, verdict: String?, note: String?) -> PanelValue {
        var answers = value.object ?? [:]
        var entry = answers[item]?.object ?? [:]
        if let verdict { entry["verdict"] = .string(verdict) }
        if let note { entry["note"] = note.isEmpty ? nil : .string(note) }
        answers[item] = .object(entry)
        return .object(answers)
    }

    /// An item counts as answered when it has a verdict and, if that verdict needs one, a note.
    static func answeredCount(_ value: PanelValue, items: [PanelOption], verdicts: [ReviewVerdict]) -> Int {
        items.filter { item in
            guard let chosen = verdict(value, item: item.id),
                  let rule = verdicts.first(where: { $0.id == chosen }) else { return false }
            return !rule.requiresNote || !note(value, item: item.id).trimmingCharacters(in: .whitespaces).isEmpty
        }.count
    }
}

struct PanelItemReview: View {
    let label: String
    let items: [PanelOption]
    let verdicts: [ReviewVerdict]
    @Binding var value: PanelValue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: label).font(.headline).fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(kitL("\(ItemReviewAnswer.answeredCount(value, items: items, verdicts: verdicts)) of \(items.count) answered"))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            VStack(spacing: 6) {
                ForEach(items) { item in itemRow(item) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func itemRow(_ item: PanelOption) -> some View {
        let chosen = ItemReviewAnswer.verdict(value, item: item.id)
        let needsNote = verdicts.first { $0.id == chosen }?.requiresNote ?? false
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.label).fixedSize(horizontal: false, vertical: true)
                if let description = item.description {
                    Text(verbatim: description).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 6) {
                ForEach(verdicts) { verdict in chip(verdict, item: item.id, selected: chosen == verdict.id) }
            }
            if needsNote {
                TextField(kitL("Note (required)"), text: Binding(
                    get: { ItemReviewAnswer.note(value, item: item.id) },
                    set: { value = ItemReviewAnswer.setting(value, item: item.id, verdict: nil, note: $0) }),
                    axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .accessibilityIdentifier("panel-review-note-\(item.id)")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("panel-review-\(item.id)")
    }

    private func chip(_ verdict: ReviewVerdict, item: String, selected: Bool) -> some View {
        Button {
            value = ItemReviewAnswer.setting(value, item: item, verdict: verdict.id, note: nil)
        } label: {
            Text(verbatim: verdict.label)
                .font(.callout.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundStyle(selected ? Color.accentColor : .primary)
                .background(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.06), in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Color.accentColor.opacity(0.6) : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("panel-review-\(item)-\(verdict.id)")
    }
}
