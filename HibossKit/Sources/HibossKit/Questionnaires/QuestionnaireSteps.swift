// Derives one-question-per-step pages from an existing questionnaire formSpec, client-side only.
// Exports QuestionnaireSteps, QuestionnaireStep, QuestionnaireField and QuestionnaireReviewRow.
// Completion follows the answer-schema subset the server enforces. Dependencies: panel spec/value types.

import Foundation

struct QuestionnaireField: Equatable {
    let path: String
    let label: String
    /// Per `/form` path segment: whether that key is in its parent object's `required`.
    let requiredChain: [Bool]
    /// The bound value's own schema (`$ref` resolved), or nil when the answer schema does not describe it.
    let schema: PanelValue?
    let options: [PanelValue]

    /// In its parent's `required`, and every ancestor object on the path is required or present.
    func isRequired(in state: PanelValue) -> Bool {
        guard requiredChain.last == true else { return false }
        let segments = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst(2)
        for depth in requiredChain.indices.dropLast() where !requiredChain[depth] {
            if panelValue(at: "/form/" + segments.prefix(depth + 1).joined(separator: "/"), in: state) == nil { return false }
        }
        return true
    }

    /// Present, and accepted by the field's own schema constraints.
    func isAnswered(in state: PanelValue) -> Bool {
        panelValue(at: path, in: state).map { questionnaireValueSatisfies($0, schema: schema) } ?? false
    }
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
        var intro: [String] = []
        var pending: [String] = []
        var steps: [QuestionnaireStep] = []
        for id in root.children where spec.elements[id] != nil {
            let fields = Self.fields(in: id, spec: spec, answerSchema: answerSchema)
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
        return steps[index].fields.filter { $0.isRequired(in: state) && !$0.isAnswered(in: state) }
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
                    value: value.map { questionnaireAnswerText($0, options: field.options) },
                    required: field.isRequired(in: state))
            }
        }
    }

    private static func fields(in id: String, spec: PanelSpec, answerSchema: PanelValue) -> [QuestionnaireField] {
        var visited: Set<String> = []
        var fields: [QuestionnaireField] = []
        func visit(_ id: String) {
            guard visited.insert(id).inserted, let element = spec.elements[id] else { return }
            if inputTypes.contains(element.type), let path = element.props["value"]?.object?["$bindState"]?.string {
                let (chain, schema) = requirement(of: path, in: answerSchema)
                fields.append(QuestionnaireField(
                    path: path, label: element.props["label"]?.string ?? path, requiredChain: chain,
                    schema: schema, options: element.props["options"]?.array ?? []))
            }
            element.children.forEach(visit)
        }
        visit(id)
        return fields
    }

    /// Walks a `/form/...` binding through nested `properties`, noting each key's `required` membership.
    private static func requirement(of path: String, in answerSchema: PanelValue) -> ([Bool], PanelValue?) {
        guard path.hasPrefix("/form/") else { return ([], nil) }
        var node: PanelValue? = resolved(answerSchema, root: answerSchema)
        var chain: [Bool] = []
        for raw in path.dropFirst("/form/".count).split(separator: "/", omittingEmptySubsequences: false) {
            let key = raw.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
            let object = node?.object
            chain.append(object?["required"]?.array?.contains(.string(key)) ?? false)
            node = object?["properties"]?.object?[key].map { resolved($0, root: answerSchema) }
        }
        return (chain, node)
    }

    /// One local `#/$defs/<name>` hop, as the server resolves a schema node.
    private static func resolved(_ node: PanelValue, root: PanelValue) -> PanelValue {
        guard let ref = node.object?["$ref"]?.string, ref.hasPrefix("#/$defs/") else { return node }
        return root.object?["$defs"]?.object?[String(ref.dropFirst("#/$defs/".count))] ?? node
    }
}

extension QuestionnaireModel {
    /// Step pages for the form being edited, or nil for the single-page layout.
    var steps: QuestionnaireSteps? { QuestionnaireSteps(spec: formSpec, answerSchema: editing.definition.answerSchema) }
}

/// The server's per-value checks (`answer-schema.ts`): type, enum, string length, item count, numeric bounds.
/// Conditional (`if`/`allOf`) and per-item schemas are left to the server, which stays authoritative.
func questionnaireValueSatisfies(_ value: PanelValue, schema: PanelValue?) -> Bool {
    guard let schema = schema?.object else { return true }
    if let allowed = schema["enum"]?.array, !allowed.contains(value) { return false }
    if let type = schema["type"], !questionnaireTypeMatches(type, value) { return false }
    func atLeast(_ key: String, _ count: Int) -> Bool { schema[key]?.number.map { Double(count) >= $0 } ?? true }
    func atMost(_ key: String, _ count: Int) -> Bool { schema[key]?.number.map { Double(count) <= $0 } ?? true }
    switch value {
    case let .string(text):
        return atLeast("minLength", text.utf16.count) && atMost("maxLength", text.utf16.count)
    case let .array(items):
        return atLeast("minItems", items.count) && atMost("maxItems", items.count)
    case let .number(number):
        return (schema["minimum"]?.number.map { number >= $0 } ?? true)
            && (schema["maximum"]?.number.map { number <= $0 } ?? true)
            && (schema["exclusiveMinimum"]?.number.map { number > $0 } ?? true)
            && (schema["exclusiveMaximum"]?.number.map { number < $0 } ?? true)
    default: return true
    }
}

private func questionnaireTypeMatches(_ type: PanelValue, _ value: PanelValue) -> Bool {
    if let types = type.array { return types.contains { questionnaireTypeMatches($0, value) } }
    switch (type.string, value) {
    case ("string", .string), ("boolean", .bool), ("null", .null), ("array", .array), ("object", .object),
         ("number", .number): return true
    case let ("integer", .number(number)): return number.rounded() == number
    default: return type.string == nil
    }
}
