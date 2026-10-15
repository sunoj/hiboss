// Measures the natural pieces of the live option surface, independently of its viewport.
// Exports: height preferences and the view measurement modifier.
// Dependencies: SwiftUI; the controller consumes only changes to the summed natural height.

import SwiftUI

enum OptionSurfaceInsets {
    static let horizontal: CGFloat = 18
    static let top: CGFloat = 13
    static let bottom: CGFloat = 16
}

enum OptionHeightPart: Hashable {
    case header, question, actions
}

struct OptionNaturalHeights: PreferenceKey {
    static let defaultValue: [OptionHeightPart: CGSize] = [:]

    static func reduce(value: inout [OptionHeightPart: CGSize],
                       nextValue: () -> [OptionHeightPart: CGSize]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct ResolvedNaturalHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

@MainActor
final class OptionQuestionGeometry {
    var textFrame: CGRect = .zero
}

struct QuestionTextBounds: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

extension View {
    func reportNaturalHeight(_ part: OptionHeightPart) -> some View {
        background(GeometryReader { geometry in
            let height = part == .question
                ? max(OptionMessageBody.minimumHeight, geometry.size.height) : geometry.size.height
            Color.clear.preference(key: OptionNaturalHeights.self,
                value: [part: CGSize(width: geometry.size.width, height: height)])
        })
    }
}
