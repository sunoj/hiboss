// Host-owned form state for the mixed native/web panel.
// Exports: PanelStore and PanelActionResult.
// Dependencies: Combine, SwiftUI Binding, JSON Pointer helpers, and fixture defaults.

import Combine
import SwiftUI

enum PanelActionResult: Sendable { case idle, submitted }

@MainActor
final class PanelStore: ObservableObject {
    @Published private(set) var state: JSONValue
    @Published private(set) var actionResult: PanelActionResult = .idle

    init(fixture: PanelFixture) {
        state = .object(["form": fixture.defaults])
    }

    func binding(for path: String) -> Binding<JSONValue> {
        Binding(
            get: { [weak self] in self.flatMap { value(at: path, in: $0.state) } ?? .null },
            set: { [weak self] value in self?.write(value, at: path) }
        )
    }

    func applyHostDelta(path: String, value: JSONValue) {
        write(value, at: path)
    }

    func perform(_ action: PanelAction?) {
        guard action?.action == "submitRequest" else { return }
        actionResult = .submitted
    }

    func draftDescription() -> String {
        let strategy = value(at: "/form/strategy", in: state)?.displayText ?? ""
        let traffic = value(at: "/form/trafficPercent", in: state)?.displayText ?? ""
        return "strategy=\(strategy) trafficPercent=\(traffic)"
    }

    private func write(_ value: JSONValue, at path: String) {
        guard let updated = setValue(value, at: path, in: state) else { return }
        state = updated
    }
}
