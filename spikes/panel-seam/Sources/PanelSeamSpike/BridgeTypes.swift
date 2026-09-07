// Codable messages crossing the display-only native/web boundary.
// Exports: HostMessage and ViewMessage.
// Dependencies: Foundation and JSONValue.

import Foundation

enum HostMessageKind: String, Encodable { case mount, applyTaskState }
enum ViewMessageKind: String, Decodable { case contentSizeChanged, renderFailed }

struct HostMessage: Encodable {
    let kind: HostMessageKind
    let panelId: String
    let definition: [String: JSONValue]?
    let state: [String: JSONValue]?
    let sequence: Int
}

struct ViewMessage: Decodable {
    let kind: ViewMessageKind
    let panelId: String
    let contentHeight: Double?
    let observedSequence: Int?
    let observedAtMs: Double?
    let message: String?
}
