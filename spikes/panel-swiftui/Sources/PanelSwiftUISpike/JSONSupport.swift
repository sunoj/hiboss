// JSON Pointer, expression, and answer-schema helpers for the adapter.
// Exports: JSONPointer, ExpressionContext, resolve, setValue, validateAnswers.
// Dependencies: JSONValue from Types.swift and Foundation.

import Foundation

struct JSONPointer: Sendable {
    let segments: [String]

    init?(_ raw: String) {
        guard raw.isEmpty || raw.hasPrefix("/") else { return nil }
        let parts = raw.isEmpty ? [] : raw.dropFirst().split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let decoded = parts.compactMap(Self.decode)
        guard decoded.count == parts.count else { return nil }
        guard decoded.allSatisfy({ !["__proto__", "prototype", "constructor"].contains($0) }) else { return nil }
        segments = decoded
    }

    private static func decode(_ segment: String) -> String? {
        var result = ""
        var index = segment.startIndex
        while index < segment.endIndex {
            guard segment[index] == "~" else { result.append(segment[index]); index = segment.index(after: index); continue }
            let next = segment.index(after: index)
            guard next < segment.endIndex, segment[next] == "0" || segment[next] == "1" else { return nil }
            result.append(segment[next] == "0" ? "~" : "/")
            index = segment.index(after: next)
        }
        return result
    }
}

struct ExpressionContext: Sendable {
    let state: JSONValue
    let item: JSONValue?
    let index: Int?
    let itemPath: String?

    init(state: JSONValue, item: JSONValue?, index: Int?, itemPath: String? = nil) {
        self.state = state
        self.item = item
        self.index = index
        self.itemPath = itemPath
    }
}

func value(at pointer: String, in root: JSONValue) -> JSONValue? {
    guard let path = JSONPointer(pointer) else { return nil }
    var current = root
    for segment in path.segments {
        if let object = current.object, let next = object[segment] { current = next; continue }
        if let array = current.array, let index = Int(segment), array.indices.contains(index) { current = array[index]; continue }
        return nil
    }
    return current
}

func setValue(_ value: JSONValue, at pointer: String, in root: JSONValue) -> JSONValue? {
    guard let path = JSONPointer(pointer) else { return nil }
    return path.segments.isEmpty ? value : setValue(value, segments: path.segments[...], in: root)
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
        guard let index = Int(segment), array.indices.contains(index) else { return nil }
        var copy = array
        guard let updated = setValue(value, segments: rest, in: copy[index]) else { return nil }
        copy[index] = updated
        return .array(copy)
    default: return nil
    }
}

func resolveExpression(_ expression: JSONValue, context: ExpressionContext) -> JSONValue? {
    guard let object = expression.object, object.count == 1, let key = object.keys.first, let operand = object[key] else { return expression }
    switch key {
    case "$state", "$bindState": return operand.string.flatMap { value(at: $0, in: context.state) }
    case "$item", "$bindItem": return operand.string.flatMap { value(at: $0, in: context.item ?? .null) }
    case "$index": return operand.number.map { .number($0) } ?? context.index.map { .number(Double($0)) }
    default: return nil
    }
}

func bindingPath(_ expression: JSONValue) -> String? {
    guard let object = expression.object, object.count == 1 else { return nil }
    for key in ["$bindState", "$bindItem"] where object[key]?.string != nil { return object[key]?.string }
    return nil
}

struct ValidationIssue: Equatable, Sendable {
    let path: String
    let message: String
}

func validateAnswers(_ value: JSONValue, against schema: JSONValue) -> [ValidationIssue] {
    var issues: [ValidationIssue] = []
    validate(value, schema: schema, path: "", issues: &issues)
    return issues
}

private func validate(_ value: JSONValue, schema: JSONValue, path: String, issues: inout [ValidationIssue]) {
    guard let object = schema.object else { return }
    if let enumValues = object["enum"]?.array, !enumValues.contains(value) { issues.append(.init(path: path, message: "Choose an allowed value")) }
    if let type = object["type"]?.string, !matches(value, type: type) { issues.append(.init(path: path, message: "Expected \(type)")); return }
    if let minimum = object["minimum"]?.number, let actual = value.number, actual < minimum { issues.append(.init(path: path, message: "Must be at least \(minimum)")) }
    if let maximum = object["maximum"]?.number, let actual = value.number, actual > maximum { issues.append(.init(path: path, message: "Must be at most \(maximum)")) }
    if let objectValue = value.object, let properties = object["properties"]?.object {
        let required = object["required"]?.array?.compactMap { $0.string } ?? []
        for key in required where objectValue[key] == nil { issues.append(.init(path: path + "/" + key, message: "Required")) }
        for (key, child) in objectValue { if let childSchema = properties[key] { validate(child, schema: childSchema, path: path + "/" + key, issues: &issues) } }
        if object["additionalProperties"]?.bool == false { for (key, _) in objectValue where properties[key] == nil { issues.append(.init(path: path + "/" + key, message: "Unexpected field")) } }
    }
    if let allOf = object["allOf"]?.array { for rule in allOf { validateConditional(value, rule: rule, path: path, issues: &issues) } }
}

private func validateConditional(_ value: JSONValue, rule: JSONValue, path: String, issues: inout [ValidationIssue]) {
    guard let ruleObject = rule.object, let condition = ruleObject["if"], let thenSchema = ruleObject["then"], matchesCondition(value, schema: condition) else { return }
    validate(value, schema: thenSchema, path: path, issues: &issues)
}

private func matches(_ value: JSONValue, type: String) -> Bool {
    switch type {
    case "object": return value.object != nil
    case "array": return value.array != nil
    case "string": return value.string != nil
    case "integer": return value.number.map { $0.rounded() == $0 } ?? false
    case "number": return value.number != nil
    case "boolean": return value.bool != nil
    case "null": return value == .null
    default: return true
    }
}

private func matchesCondition(_ value: JSONValue, schema: JSONValue) -> Bool {
    guard let object = schema.object, let properties = object["properties"]?.object, let actual = value.object else { return false }
    return properties.allSatisfy { key, child in
        guard let candidate = actual[key] else { return false }
        return child.object?["enum"]?.array?.contains(candidate) == true
    }
}
