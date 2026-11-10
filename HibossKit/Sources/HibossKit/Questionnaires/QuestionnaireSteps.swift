// Derives one-question-per-step pages from an existing questionnaire formSpec, client-side only.
// Exports QuestionnaireSteps, QuestionnaireStep, QuestionnaireField and QuestionnaireReviewRow.
// Dependencies: shared panel spec/value types and questionnaire answer formatting.

import Foundation

struct QuestionnaireField: Equatable {
    let path: String
    let label: String
    let required: Bool
    let options: [PanelValue]
}

struct QuestionnaireStep: Equatable {
    /// Elements rendered on this page: attached display items plus the step's input element.
    let elementIDs: [String]
    let fields: [QuestionnaireField]
}

struct QuestionnaireReviewRow: Identifiable, Equatable {
    let id: String
    let step: Int
    let label: String
    /// Readable answer, or nil when the field has no answer yet.
    let value: String?
    let required: Bool
}

struct QuestionnaireSteps: Equatable {
    static let inputTypes: Set<String> = ["TextInput", "TextArea", "NumberInput", "Select", "MultiSelect", "Toggle", "Slider"]
    static let minimumSteps = 3

    /// The form without submit buttons: the review page owns submission.
    let spec: PanelSpec
    /// Display items before the first step, shown with step 1.
    let intro: [String]
    let steps: [QuestionnaireStep]

    /// Nil keeps the single-page layout: the root is not a Stack/Grid or yields fewer than 3 steps.
    init?(spec original: PanelSpec, answerSchema: PanelValue) {
        let spec = original.removingSubmitControls()
        guard let root = spec.elements[spec.root], ["Stack", "Grid"].contains(root.type) else { return nil }
        let required = Set(answerSchema.object?["required"]?.array?.compactMap(\.string) ?? [])
        var intro: [String] = []
        var pending: [String] = []
        var steps: [QuestionnaireStep] = []
        for id in root.children where spec.elements[id] != nil {
            let fields = Self.fields(in: id, spec: spec, required: required)
            if fields.isEmpty {
                pending.append(id)
            } else if steps.isEmpty {
                intro = pending
                steps.append(QuestionnaireStep(elementIDs: [id], fields: fields))
                pending = []
            } else {
                steps.append(QuestionnaireStep(elementIDs: pending + [id], fields: fields))
                pending = []
            }
        }
        guard steps.count >= Self.minimumSteps, let last = steps.popLast() else { return nil }
        steps.append(QuestionnaireStep(elementIDs: last.elementIDs + pending, fields: last.fields))
        self.spec = spec
        self.intro = intro
        self.steps = steps
    }

    func missingRequired(inStep index: Int, state: PanelValue) -> [QuestionnaireField] {
        guard steps.indices.contains(index) else { return [] }
        return steps[index].fields.filter { $0.required && !questionnaireIsAnswered(panelValue(at: $0.path, in: state)) }
    }

    func isComplete(inStep index: Int, state: PanelValue) -> Bool { missingRequired(inStep: index, state: state).isEmpty }

    func allRequiredAnswered(state: PanelValue) -> Bool { steps.indices.allSatisfy { isComplete(inStep: $0, state: state) } }

    /// The first step with an unanswered required field, or `steps.count` (the review page).
    func initialIndex(state: PanelValue) -> Int {
        steps.indices.first { !isComplete(inStep: $0, state: state) } ?? steps.count
    }

    func reviewRows(state: PanelValue) -> [QuestionnaireReviewRow] {
        steps.enumerated().flatMap { index, step in
            step.fields.map { field in
                let value = panelValue(at: field.path, in: state)
                return QuestionnaireReviewRow(
                    id: field.path, step: index, label: field.label,
                    value: questionnaireIsAnswered(value) ? questionnaireAnswerText(value ?? .null, options: field.options) : nil,
                    required: field.required)
            }
        }
    }

    private static func fields(in id: String, spec: PanelSpec, required: Set<String>) -> [QuestionnaireField] {
        var visited: Set<String> = []
        var fields: [QuestionnaireField] = []
        func visit(_ id: String) {
            guard visited.insert(id).inserted, let element = spec.elements[id] else { return }
            if inputTypes.contains(element.type), let path = element.props["value"]?.object?["$bindState"]?.string {
                fields.append(QuestionnaireField(
                    path: path, label: element.props["label"]?.string ?? path,
                    required: formKey(path).map(required.contains) ?? false,
                    options: element.props["options"]?.array ?? []))
            }
            element.children.forEach(visit)
        }
        visit(id)
        return fields
    }

    /// The top-level answer key a `/form/...` binding writes, as `answerSchema.required` names it.
    private static func formKey(_ path: String) -> String? {
        guard path.hasPrefix("/form/") else { return nil }
        let segment = path.dropFirst("/form/".count).split(separator: "/", omittingEmptySubsequences: false).first ?? ""
        return segment.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
    }
}

extension QuestionnaireModel {
    /// Step pages for the form being edited, or nil for the single-page layout.
    var steps: QuestionnaireSteps? { QuestionnaireSteps(spec: formSpec, answerSchema: editing.definition.answerSchema) }
}

/// Whether a bound value counts as an answer: present, and not an empty string or empty selection.
func questionnaireIsAnswered(_ value: PanelValue?) -> Bool {
    switch value {
    case nil, .null: return false
    case let .string(text): return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case let .array(values): return !values.isEmpty
    default: return true
    }
}
