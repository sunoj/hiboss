// JSON pointer access and display helpers for shared panel values.
// Exports: PanelValue accessors, displayText, and panelValue(at:in:).
// Dependencies: Foundation and the shared PanelValue contract.

import Foundation

extension PanelValue {
    public var object: [String: PanelValue]? {
        if case let .object(value) = self { value } else { nil }
    }

    public var array: [PanelValue]? {
        if case let .array(value) = self { value } else { nil }
    }

    public var string: String? {
        if case let .string(value) = self { value } else { nil }
    }

    public var number: Double? {
        if case let .number(value) = self { value } else { nil }
    }

    public var bool: Bool? {
        if case let .bool(value) = self { value } else { nil }
    }

    public var displayText: String {
        switch self {
        case let .string(value): value
        case let .number(value): Int(exactly: value).map(String.init) ?? String(value)
        case let .bool(value): value ? "On" : "Off"
        default: ""
        }
    }
}

public func panelValue(at pointer: String, in root: PanelValue) -> PanelValue? {
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
