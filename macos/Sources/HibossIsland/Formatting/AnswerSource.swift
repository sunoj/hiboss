// Canonical platform spelling and visibility for recorded answer attribution.
// Exports: AnswerSource.label and visibleLabel; Mac answers omit source attribution.
// Dependencies: Foundation for capitalization of unknown source names.

import Foundation

enum AnswerSource {
    static func label(_ source: String) -> String {
        switch source.lowercased() {
        case "ios": "iOS"
        case "ipados": "iPadOS"
        case "macos": "macOS"
        case "watchos": "watchOS"
        case "cli": "CLI" // i18n-exempt: canonical answer-source identifier
        case "web": "Web" // i18n-exempt: canonical answer-source identifier
        case "telegram": "Telegram" // i18n-exempt: service brand name
        case "discord": "Discord" // i18n-exempt: service brand name
        default: source.capitalized
        }
    }

    static func visibleLabel(_ source: String) -> String? {
        source.isEmpty || source.lowercased() == "macos" ? nil : label(source)
    }
}
