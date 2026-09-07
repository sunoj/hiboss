// JSON Pointer reads and writes for native control bindings in the seam harness.
// Exports: value(at:in:) and setValue(_:at:in:).
// Dependencies: JSONValue and Foundation.

import Foundation

func value(at pointer: String, in root: JSONValue) -> JSONValue? {
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

func setValue(_ value: JSONValue, at pointer: String, in root: JSONValue) -> JSONValue? {
    guard pointer.isEmpty || pointer.first == "/" else { return nil }
    let segments = pointer.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map(String.init)
    return setValue(value, segments: segments[...], in: root)
}

private func setValue(_ value: JSONValue, segments: ArraySlice<String>, in root: JSONValue) -> JSONValue? {
    guard let segment = segments.first else { return value }
    let rest = segments.dropFirst()
    switch root {
    case let .object(object):
        var copy = object
        let child = copy[segment] ?? (rest.isEmpty ? .null : .object([:]))
        guard let updated = setValue(value, segments: rest, in: child) else { return nil }
        copy[segment] = updated
        return .object(copy)
    case let .array(array):
        guard let index = Int(segment), array.indices.contains(index), let updated = setValue(value, segments: rest, in: array[index]) else { return nil }
        var copy = array
        copy[index] = updated
        return .array(copy)
    default: return nil
    }
}
