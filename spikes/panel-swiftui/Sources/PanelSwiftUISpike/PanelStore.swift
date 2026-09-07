// Main-actor state and action adapter for live panel rendering.
// Exports: PanelStore and PanelActionResult.
// Dependencies: Combine, SwiftUI Binding, JSON pointer helpers, and fixture models.

import Combine
import SwiftUI

enum PanelActionResult: Sendable {
    case idle
    case submitted
    case rejected([ValidationIssue])
    case opened(String)
}

@MainActor
final class PanelStore: ObservableObject {
    @Published private(set) var state: JSONValue
    @Published private(set) var revision = 0
    @Published private(set) var actionResult: PanelActionResult = .idle
    let fixture: PanelFixture

    init(fixture: PanelFixture) {
        self.fixture = fixture
        let base = fixture.initialState?.object ?? [:]
        var state = JSONValue.object(base)
        if let defaults = fixture.defaults { state = setValue(defaults, at: "/form", in: state) ?? state }
        self.state = state
    }

    func resolve(_ expression: JSONValue, context: ExpressionContext = .init(state: .null, item: nil, index: nil)) -> JSONValue? {
        resolveExpression(expression, context: .init(state: state, item: context.item, index: context.index, itemPath: context.itemPath))
    }

    func binding(for expression: JSONValue, context: ExpressionContext = .init(state: .null, item: nil, index: nil)) -> Binding<JSONValue>? {
        guard let path = bindingPath(expression) else { return nil }
        let fullPath = pathForBinding(path, context: context)
        return Binding(
            get: { [weak self] in self.flatMap { value(at: fullPath, in: $0.state) } ?? .null },
            set: { [weak self] value in self?.write(value, at: fullPath) }
        )
    }

    func applyHostDelta(path: String, value: JSONValue) {
        write(value, at: path)
    }

    func perform(_ action: PanelAction) {
        switch action.action {
        case "submitRequest": submit()
        case "openPanel": actionResult = .opened(action.params?["panelId"]?.string ?? "")
        default: actionResult = .idle
        }
    }

    private func pathForBinding(_ path: String, context: ExpressionContext) -> String {
        guard path.first == "/", let itemPath = context.itemPath else { return path }
        return itemPath + path
    }

    private func write(_ value: JSONValue, at path: String) {
        guard let updated = setValue(value, at: path, in: state) else { return }
        state = updated
        revision += 1
    }

    private func submit() {
        let answers = value(at: "/form", in: state) ?? .object([:])
        let issues = fixture.answerSchema.map { validateAnswers(answers, against: $0) } ?? []
        actionResult = issues.isEmpty ? .submitted : .rejected(issues)
    }
}
