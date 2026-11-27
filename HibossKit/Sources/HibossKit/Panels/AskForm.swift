// A form ask's one catalog v2 input, its completeness rule, and the readable reply summary.
// Exports: AskForm, AskFormAnswering (the reply seam), and AskForm.summary(_:).
// Dependencies: PanelValue, PanelOption, ReviewVerdict and the ordering/review answer rules.

import Foundation

/// `metadata.form` on an ask: `{catalogVersion: 2, input: {type, props}}` bound to `/form/answer`.
public struct AskForm: Equatable, Sendable {
    public enum Kind: String, Sendable { case rankedChoice = "RankedChoice", itemReview = "ItemReview" }

    public let kind: Kind
    public let props: [String: PanelValue]

    public init?(_ value: PanelValue?) {
        guard let object = value?.object, object["catalogVersion"]?.number == 2,
              let input = object["input"]?.object, let type = input["type"]?.string,
              let kind = Kind(rawValue: type), let props = input["props"]?.object else { return nil }
        self.kind = kind
        self.props = props
    }

    public var label: String { props["label"]?.string ?? "" }
    var options: [PanelOption] { entries("options") }
    var items: [PanelOption] { entries("items") }
    var topK: Int? { props["topK"]?.number.map { Int($0) } }

    var verdicts: [ReviewVerdict] {
        props["verdicts"]?.array?.compactMap { value -> ReviewVerdict? in
            guard let object = value.object, let id = object["id"]?.string, let label = object["label"]?.string
            else { return nil }
            return ReviewVerdict(id: id, label: label, requiresNote: object["requiresNote"]?.bool ?? false)
        } ?? []
    }

    private func entries(_ key: String) -> [PanelOption] {
        props[key]?.array?.compactMap { value -> PanelOption? in
            guard let object = value.object, let id = object["id"]?.string, let label = object["label"]?.string
            else { return nil }
            return PanelOption(id: id, label: label, description: object["description"]?.string)
        } ?? []
    }

    /// The value as it would be submitted: a ranking defaults to the shown order.
    public func answer(from value: PanelValue) -> PanelValue {
        switch kind {
        case .rankedChoice:
            let order = RankedChoiceOrder.order(stored: value.array?.compactMap(\.string), options: options)
            return .array(RankedChoiceOrder.answer(order, topK: topK).map(PanelValue.string))
        case .itemReview:
            return value
        }
    }

    /// Submit is enabled only when the server's derived schema would accept the answer.
    public func isComplete(_ value: PanelValue) -> Bool {
        switch kind {
        case .rankedChoice: return true
        case .itemReview:
            return ItemReviewAnswer.answeredCount(value, items: items, verdicts: verdicts) == items.count
        }
    }

    /// The reply's readable body for the thread, Discord and older clients; agents read `answers`.
    public func summary(_ value: PanelValue) -> String {
        switch kind {
        case .rankedChoice:
            let labels = answer(from: value).array?.compactMap(\.string).enumerated().map { index, id in
                "\(index + 1). \(options.first { $0.id == id }?.label ?? id)"
            } ?? []
            return labels.joined(separator: "\n")
        case .itemReview:
            return items.map { item in
                let chosen = ItemReviewAnswer.verdict(value, item: item.id)
                let verdict = verdicts.first { $0.id == chosen }?.label ?? "—"
                let note = ItemReviewAnswer.note(value, item: item.id)
                return note.isEmpty ? "\(item.label): \(verdict)" : "\(item.label): \(verdict) (\(note))"
            }.joined(separator: "\n")
        }
    }
}

/// Answers a form ask: the server needs `answers` beside the readable body.
public protocol AskFormAnswering: Sendable {
    func reply(to messageID: MessageID, with body: String, answers: PanelValue) async throws -> ReplyOutcome
}
