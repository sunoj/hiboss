// Single mapping from a progress-post model string to a vendor monogram identity.
// Exports: ProgressModelVendor.
// Dependencies: Foundation only — UI tints live in the client chip view.

import Foundation

/// Vendor derived from a model id. Keep this the only place that maps prefixes.
public enum ProgressModelVendor: String, Equatable, Sendable, CaseIterable {
    case anthropic
    case openAI
    case google
    case xAI
    case unknown

    /// One-letter mark drawn by the client (not a trademarked logo asset).
    public var monogram: String {
        switch self {
        case .anthropic: "A"
        case .openAI: "O"
        case .google: "G"
        case .xAI: "X"
        case .unknown: "?"
        }
    }

    public static func from(model: String?) -> ProgressModelVendor {
        guard let model, !model.isEmpty else { return .unknown }
        let lower = model.lowercased()
        if lower.hasPrefix("claude") { return .anthropic }
        if lower.hasPrefix("gpt") { return .openAI }
        if isOpenAIOSeries(lower) { return .openAI }
        if lower.hasPrefix("gemini") { return .google }
        if lower.hasPrefix("grok") { return .xAI }
        return .unknown
    }

    /// `o1`, `o3-mini`, … — digit after `o` so bare words like "opus" stay unknown.
    private static func isOpenAIOSeries(_ lower: String) -> Bool {
        guard lower.hasPrefix("o"), lower.count >= 2 else { return false }
        let second = lower[lower.index(after: lower.startIndex)]
        return second.isNumber
    }
}
