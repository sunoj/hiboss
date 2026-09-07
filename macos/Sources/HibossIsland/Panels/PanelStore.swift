// Host-owned state and answer assembly for the native controls in a panel.
// Exports: PanelStore and PanelActionResult.
// Dependencies: Combine, SwiftUI Binding, PanelJSONValue, and JSON Pointer helpers.

import Combine
import SwiftUI

enum PanelActionResult: Sendable { case idle, submitted(PanelJSONValue) }

@MainActor
final class PanelStore: ObservableObject {
    @Published private(set) var state: PanelJSONValue
    @Published private(set) var actionResult: PanelActionResult = .idle

    init(fixture: PanelFixture) { state = fixture.initialState }

    func binding(for path: String) -> Binding<PanelJSONValue> {
        Binding(
            get: { [weak self] in self.flatMap { panelValue(at: path, in: $0.state) } ?? .null },
            set: { [weak self] value in self?.write(value, at: path) }
        )
    }

    func setText(_ text: String, at path: String) {
        write(Double(text).map(PanelJSONValue.number) ?? .string(text), at: path)
    }

    func setBool(_ value: Bool, at path: String) { write(.bool(value), at: path) }

    func perform(_ action: PanelAction?) {
        guard action?.action == "submitRequest" else { return }
        let answer = panelValue(at: "/form", in: state) ?? state
        actionResult = .submitted(answer)
    }

    var submittedAnswerText: String? {
        guard case let .submitted(answer) = actionResult,
              let data = try? JSONEncoder.pretty.encode(answer) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ value: PanelJSONValue, at path: String) {
        guard let updated = panelSetValue(value, at: path, in: state) else { return }
        state = updated
    }
}

private extension JSONEncoder {
    static let pretty: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

func panelValue(at pointer: String, in root: PanelJSONValue) -> PanelJSONValue? {
    guard pointer.isEmpty || pointer.first == "/" else { return nil }
    var current = root
    for rawSegment in pointer.split(separator: "/", omittingEmptySubsequences: false).dropFirst() {
        let segment = rawSegment.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
        if let object = current.object, let next = object[segment] { current = next; continue }
        if let array = current.array, let index = Int(segment), array.indices.contains(index) { current = array[index]; continue }
        return nil
    }
    return current
}

func panelSetValue(_ value: PanelJSONValue, at pointer: String, in root: PanelJSONValue) -> PanelJSONValue? {
    guard pointer.isEmpty || pointer.first == "/" else { return nil }
    let segments = pointer.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map(String.init)
    return panelSetValue(value, segments: segments[...], in: root)
}

private func panelSetValue(_ value: PanelJSONValue, segments: ArraySlice<String>, in root: PanelJSONValue) -> PanelJSONValue? {
    guard let segment = segments.first else { return value }
    let rest = segments.dropFirst()
    switch root {
    case let .object(object):
        var copy = object
        let child = copy[segment] ?? (rest.isEmpty ? .null : .object([:]))
        guard let updated = panelSetValue(value, segments: rest, in: child) else { return nil }
        copy[segment] = updated
        return .object(copy)
    case let .array(array):
        guard let index = Int(segment), array.indices.contains(index), let updated = panelSetValue(value, segments: rest, in: array[index]) else { return nil }
        var copy = array
        copy[index] = updated
        return .array(copy)
    default: return nil
    }
}
