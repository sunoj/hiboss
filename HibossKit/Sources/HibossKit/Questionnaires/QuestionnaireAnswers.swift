// Converts accepted structured answers into labelled, readable native receipts.
// Exports answer rows and QuestionnaireAnswerView; option IDs use their display labels.
// Dependencies: SwiftUI, form spec traversal, and JSON pointer helpers.

import SwiftUI

struct QuestionnaireAnswerRow: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
}

func questionnaireAnswerRows(spec: PanelSpec, answers: PanelValue) -> [QuestionnaireAnswerRow] {
    var rows: [QuestionnaireAnswerRow] = []
    var visited: Set<String> = []
    var covered: Set<String> = []
    let root: PanelValue = .object(["form": answers])
    func visit(_ id: String) {
        guard visited.insert(id).inserted, let element = spec.elements[id] else { return }
        if let path = element.props["value"]?.object?["$bindState"]?.string,
           path.hasPrefix("/form/"), covered.insert(path).inserted {
            rows.append(QuestionnaireAnswerRow(id: path, label: element.props["label"]?.string ?? path,
                value: answerText(panelValue(at: path, in: root) ?? .null, options: element.props["options"]?.array ?? [])))
        }
        element.children.forEach(visit)
    }
    visit(spec.root)
    func remainder(_ value: PanelValue, path: String, labels: [String]) {
        guard !covered.contains(path) else { return }
        if let object = value.object {
            for key in object.keys.sorted() {
                let segment = key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
                if let child = object[key] { remainder(child, path: path + "/" + segment, labels: labels + [key]) }
            }
        } else {
            rows.append(QuestionnaireAnswerRow(id: path, label: labels.joined(separator: " · "), value: answerText(value)))
        }
    }
    remainder(answers, path: "/form", labels: [])
    return rows
}

private func answerText(_ value: PanelValue, options: [PanelValue] = []) -> String {
    switch value {
    case .null: return kitL("Not provided")
    case let .bool(value): return value ? kitL("Yes") : kitL("No")
    case let .array(values): return values.isEmpty ? kitL("None selected") : values.map { answerText($0, options: options) }.joined(separator: ", ")
    case let .object(values): return values.keys.sorted().map { "\($0): \(answerText(values[$0] ?? .null))" }.joined(separator: "\n")
    case let .string(value):
        return options.first { $0.object?["id"]?.string == value }?.object?["label"]?.string ?? (value.isEmpty ? kitL("Not provided") : value)
    case .number: return value.displayText
    }
}

struct QuestionnaireAnswerView: View {
    let record: QuestionnaireRecord
    let submission: QuestionnaireSubmission

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(kitL("Answer saved"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            ForEach(questionnaireAnswerRows(spec: record.definition.formSpec, answers: submission.answers)) { row in
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.label).font(.caption).foregroundStyle(.secondary)
                    Text(row.value).font(.callout).textSelection(.enabled)
                }.accessibilityElement(children: .combine)
            }
            if let date = panelDate(submission.acceptedAt) {
                Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            }
            Label(submission.delivery == "delivered" ? kitL("Received by agent") : kitL("Waiting for agent receipt"),
                  systemImage: submission.delivery == "delivered" ? "checkmark.bubble" : "clock")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
