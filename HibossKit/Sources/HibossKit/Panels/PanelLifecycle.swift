// Task lifecycle, boss placement, and server-clock freshness contracts.
// Exports PanelLifecycle, PanelPreference, and terminal result presentation.
// Dependencies: Foundation Codable and SwiftUI-independent value models.

import Foundation

public enum PanelTaskState: String, Codable, Sendable {
    case running, paused, completed, failed, cancelled
    public var isTerminal: Bool { self == .completed || self == .failed || self == .cancelled }
    public var title: String { rawValue.capitalized }
    public var symbol: String {
        switch self {
        case .running: "dot.radiowaves.left.and.right"
        case .paused: "pause.circle"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        case .cancelled: "xmark.circle"
        }
    }
}
public struct PanelResult: Codable, Equatable, Sendable {
    public let title: String
    public let message: String?
    public let code: String?
}
public struct PanelLifecycle: Codable, Equatable, Sendable {
    public let taskState: PanelTaskState
    public let mode: String
    public let expectedUpdateIntervalSeconds: Int
    public let expiresAt: String?
    public let terminalAt: String?
    public let dismissAt: String?
    public let dismissalPolicy: String?
    public let result: PanelResult?
    public static let running = PanelLifecycle(taskState: .running, mode: "run", expectedUpdateIntervalSeconds: 15,
        expiresAt: nil, terminalAt: nil, dismissAt: nil, dismissalPolicy: nil, result: nil)
}
public enum PanelPlacement: String, Codable, Sendable { case automatic, pinned, archived }
public struct PanelPreference: Codable, Equatable, Sendable {
    public var preferenceVersion: Int
    public var placement: PanelPlacement
    public var seenTerminalVersion: Int?
    public var acknowledgedTerminalVersion: Int?
    public static let automatic = PanelPreference(preferenceVersion: 0, placement: .automatic)
}
public struct PanelPreferenceCommand: Encodable, Sendable {
    public let expectedPreferenceVersion: Int
    public let placement: PanelPlacement?
    public let seenTerminalVersion: Int?
    public let acknowledgedTerminalVersion: Int?
    public init(expectedPreferenceVersion: Int, placement: PanelPlacement? = nil, seenTerminalVersion: Int? = nil, acknowledgedTerminalVersion: Int? = nil) {
        self.expectedPreferenceVersion = expectedPreferenceVersion
        self.placement = placement
        self.seenTerminalVersion = seenTerminalVersion
        self.acknowledgedTerminalVersion = acknowledgedTerminalVersion
    }
}
public enum PanelWallSection: String, CaseIterable, Identifiable { case active = "Active", results = "Results", archived = "Archived"
    public var id: String { rawValue }
}
public func panelDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}
