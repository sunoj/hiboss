// One brand-casing map for answer sources and channels, plus the shared attribution copy.
// Exports: AnswerSource (label, visibleLabel) and AnswerAttribution (answered-on, timeout default).
// Dependencies: Foundation and HibossKit's localized catalog (kitL).

import Foundation

public enum AnswerSource {
    /// Brand casing for a raw source or channel tag; `.capitalized` only for unknown values.
    public static func label(_ source: String) -> String {
        switch source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ios": "iOS"
        case "ipados": "iPadOS"
        case "macos", "mac": "macOS"
        case "watchos": "watchOS"
        case "cli": "CLI" // i18n-exempt: canonical answer-source identifier
        case "web": "Web" // i18n-exempt: canonical answer-source identifier
        case "api": "API" // i18n-exempt: canonical answer-source identifier
        case "telegram": "Telegram" // i18n-exempt: service brand name
        case "discord": "Discord" // i18n-exempt: service brand name
        default: source.capitalized
        }
    }

    /// The label to attribute, or nil for an empty source or one naming this client's own platform.
    public static func visibleLabel(_ source: String?, hiding local: String) -> String? {
        guard let source, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let text = label(source)
        return text == label(local) ? nil : text
    }
}

/// Attribution wording shared by every client; a timeout default never reads as the boss's answer.
public enum AnswerAttribution {
    public static func answeredOn(_ source: String) -> String { kitL("Answered on \(source)") }
    public static var answered: String { kitL("Answered") }
    public static var autoSelected: String { kitL("Auto-selected when time ran out") }
    public static var defaultPicked: String { kitL("Default picked · not approval") }

    public static func text(isAutoDefault: Bool, sourceLabel: String?) -> String {
        if isAutoDefault { return autoSelected }
        return sourceLabel.map(answeredOn) ?? answered
    }
}
