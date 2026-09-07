// Typed messages exchanged by the native host and the bundled panel view.
// Exports: HostMessage, ViewMessage, and bridge payload types.
// Dependencies: Foundation and JSONValue.

import Foundation

enum HostMessageKind: String, Encodable { case mount, applyTaskState, requestStatus }
enum ViewMessageKind: String, Decodable { case draftChanged, actionRequested, contentSizeChanged, renderFailed }

struct HostMessage: Encodable {
    let kind: HostMessageKind
    let panelId: String
    var fixture: String?
    var definition: [String: JSONValue]?
    var state: [String: JSONValue]?
    var sequence: Int?
    var status: String?
    var appearance: String?
}

struct DraftChange: Decodable { let path: String; let value: JSONValue }

struct ViewMessage: Decodable {
    let kind: ViewMessageKind
    let panelId: String
    let changes: [DraftChange]?
    let action: String?
    let arguments: [String: JSONValue]?
    let contentHeight: Double?
    let observedSequence: Int?
    let observedAtMs: Double?
    let classification: String?
    let message: String?
}
