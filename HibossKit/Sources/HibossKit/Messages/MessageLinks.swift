// Turns bare http(s) URLs in message text into tappable, underlined links.
// Exports MessageMarkdown.plainLinks and the linker that MessageMarkdown.inline applies.
// Dependencies: Foundation NSDataDetector, SwiftUI text attributes; code spans stay text.

import Foundation
import SwiftUI

extension MessageMarkdown {
    /// Plain text (a title, a note) with its bare web URLs linked and nothing else interpreted.
    public static func plainLinks(_ source: String) -> AttributedString {
        var text = AttributedString(source)
        linkBareURLs(in: &text)
        return text
    }

    /// Only text that spells out `http://` or `https://` is linked, so a file name such as
    /// `config.json` never becomes a guessed web address.
    static func linkBareURLs(in text: inout AttributedString) {
        // The Markdown parser links bare URLs too, but swallows Chinese text that follows one
        // without a space. Its links are spelled as their own URL; `[label](url)` links are kept.
        for run in text.runs {
            guard let link = run.link else { continue }
            let spelled = String(text[run.range].characters)
            if spelled == link.absoluteString || spelled == link.absoluteString.removingPercentEncoding {
                text[run.range].link = nil
            }
        }
        let string = String(text.characters)
        let matches = string.localizedCaseInsensitiveContains("http")
            ? linkDetector?.matches(in: string, range: NSRange(string.startIndex..., in: string)) ?? [] : []
        for match in matches {
            guard let detected = Range(match.range, in: string),
                  let found = webURLRange(in: string, detected),
                  let url = URL(string: String(string[found])) else { continue }
            let start = text.characters.index(text.startIndex,
                offsetBy: string.distance(from: string.startIndex, to: found.lowerBound))
            let end = text.characters.index(start, offsetBy: string.distance(from: found.lowerBound,
                to: found.upperBound))
            let range = start..<end
            let taken = text[range].runs.contains {
                $0.link != nil || $0.inlinePresentationIntent?.contains(.code) == true
            }
            if !taken { text[range].link = url }
        }
        // The iOS accent matches body text, so colour alone would not mark a link.
        for run in text.runs where run.link != nil {
            text[run.range].swiftUI.underlineStyle = .single
        }
    }

    /// The detector reads Chinese text written straight after a URL ("…v1.0.6，下载") as part of
    /// it, so the link ends at the first non-ASCII character, then sheds trailing punctuation.
    private static func webURLRange(in string: String, _ detected: Range<String.Index>) -> Range<String.Index>? {
        let candidate = string[detected]
        let lowered = candidate.lowercased()
        guard lowered.hasPrefix("http://") || lowered.hasPrefix("https://") else { return nil }
        var end = candidate.firstIndex { !$0.isASCII } ?? candidate.endIndex
        // A closing bracket is trimmed only while unbalanced; counts are taken once, so this is linear.
        var unmatched: [Character: Int] = [")": 0, "]": 0]
        for character in candidate[..<end] {
            switch character {
            case "(": unmatched[")", default: 0] -= 1
            case "[": unmatched["]", default: 0] -= 1
            case ")", "]": unmatched[character, default: 0] += 1
            default: break
            }
        }
        while end > candidate.startIndex {
            let last = candidate[candidate.index(before: end)]
            if let excess = unmatched[last] {
                guard excess > 0 else { break }
                unmatched[last] = excess - 1
            } else if !".,;:!?'\"".contains(last) {
                break
            }
            end = candidate.index(before: end)
        }
        let scheme = lowered.hasPrefix("https://") ? 8 : 7
        return candidate.distance(from: candidate.startIndex, to: end) > scheme
            ? candidate.startIndex..<end : nil
    }

    /// NSDataDetector is immutable after creation and safe to use from any thread.
    nonisolated(unsafe) private static let linkDetector =
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
}
