// Host-owned state and answer assembly for native panel controls.
// Exports: PanelStore and PanelActionResult.
// Dependencies: Combine, SwiftUI Binding, and shared PanelValue helpers.

import Combine
import SwiftUI

public enum PanelActionResult: Sendable { case idle, submitted(PanelValue) }

@MainActor
public final class PanelStore: ObservableObject {
    @Published public private(set) var state: PanelValue
    @Published public private(set) var actionResult: PanelActionResult = .idle

    public init(fixture: PanelFixture) { state = fixture.initialState }

    public func binding(for path: String) -> Binding<PanelValue> {
        Binding(
            get: { [weak self] in self.flatMap { panelValue(at: path, in: $0.state) } ?? .null },
            set: { [weak self] value in self?.write(value, at: path) }
        )
    }

    public func setText(_ text: String, at path: String) {
        write(Double(text).map(PanelValue.number) ?? .string(text), at: path)
    }

    public func setString(_ value: String, at path: String) { write(.string(value), at: path) }

    public func setNumber(_ value: Double, at path: String) { write(.number(value), at: path) }

    public func setStrings(_ values: [String], at path: String) {
        write(.array(values.map(PanelValue.string)), at: path)
    }

    public func setBool(_ value: Bool, at path: String) { write(.bool(value), at: path) }

    public func advanceDemoData(seed: Int) {
        state = advancedValue(state, seed: seed)
    }

    public func replaceTask(_ task: PanelValue) { write(task, at: "/task") }

    public func perform(_ action: PanelAction?) {
        guard action?.action == "submitRequest" else { return }
        let answer = panelValue(at: "/form", in: state) ?? state
        actionResult = .submitted(answer)
    }

    public var submittedAnswerText: String? {
        guard case let .submitted(answer) = actionResult,
              let data = try? JSONEncoder.pretty.encode(answer) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public var submissionWasEdited: Bool {
        guard case let .submitted(answer) = actionResult else { return false }
        return answer != (panelValue(at: "/form", in: state) ?? state)
    }

    private func write(_ value: PanelValue, at path: String) {
        guard let updated = panelSetValue(value, at: path, in: state) else { return }
        state = updated
    }

    private func advancedValue(_ value: PanelValue, seed: Int) -> PanelValue {
        switch value {
        case let .number(number): return .number(number + Double(seed % 3 + 1))
        case let .array(values): return .array(values.map { advancedValue($0, seed: seed) })
        case let .object(values): return .object(values.mapValues { advancedValue($0, seed: seed) })
        default: return value
        }
    }
}

private extension JSONEncoder {
    static let pretty: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

private func panelSetValue(_ value: PanelValue, at pointer: String, in root: PanelValue) -> PanelValue? {
    guard pointer.isEmpty || pointer.first == "/" else { return nil }
    let segments = pointer.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map(String.init)
    return panelSetValue(value, segments: segments[...], in: root)
}

private func panelSetValue(_ value: PanelValue, segments: ArraySlice<String>, in root: PanelValue) -> PanelValue? {
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
