// Calculates top-edge Island frames from injected display measurements.
// Exports: IslandGeometry and OptionPanelLayout for panel frames and content sizing.
// Dependencies: AppKit text metrics and HibossKit's unchanged plain-screen dimensions.

import AppKit
import HibossKit

struct IslandGeometry: Equatable {
    let displayID: UInt32?
    let screenFrame: CGRect
    let visibleFrame: CGRect
    let expandedTopInset: CGFloat
    let notchFrame: CGRect?

    private static let notchSideMargin: CGFloat = 18

    init(
        screenFrame: CGRect,
        visibleFrame: CGRect? = nil,
        safeAreaTop: CGFloat = 0,
        auxiliaryTopLeftArea: CGRect? = nil,
        auxiliaryTopRightArea: CGRect? = nil,
        displayID: UInt32? = nil
    ) {
        self.displayID = displayID
        self.screenFrame = screenFrame
        self.visibleFrame = visibleFrame ?? screenFrame
        expandedTopInset = max(0, safeAreaTop)
        if safeAreaTop > 0, let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea,
            !left.isEmpty, !right.isEmpty, screenFrame.width - left.width - right.width > 0 {
            let width = screenFrame.width - left.width - right.width
            notchFrame = CGRect(
                x: screenFrame.midX - width / 2, y: screenFrame.maxY - safeAreaTop,
                width: width, height: safeAreaTop
            )
        } else {
            notchFrame = nil
        }
    }

    var collapsedFrame: CGRect {
        topFrame(
            width: max(
                AppConstants.Island.collapsedWidth, (notchFrame?.width ?? 0) + 2 * Self.notchSideMargin
            ),
            height: AppConstants.Island.collapsedHeight + expandedTopInset
        )
    }

    var hotZone: CGRect {
        notchFrame.map { collapsedFrame.union($0) } ?? collapsedFrame
    }

    func expandedFrame(contentHeight: CGFloat) -> CGRect {
        topFrame(
            width: max(AppConstants.Island.width, collapsedFrame.width),
            height: min(contentHeight + expandedTopInset, visibleFrame.height * 0.8)
        )
    }

    private func topFrame(width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: (notchFrame?.midX ?? screenFrame.midX) - width / 2,
            y: screenFrame.maxY - height, width: width, height: height
        )
    }
}

enum OptionPanelLayout {
    private static let contentHorizontalPadding: CGFloat = 36
    private static let optionTextChrome: CGFloat = 46
    private static let verticalChrome: CGFloat = 86
    private static let optionVerticalPadding: CGFloat = 18
    private static let optionSpacing: CGFloat = 7
    private static let minimumOptionHeight: CGFloat = 35
    private static let optionMediaHeight: CGFloat = 128
    private static let minimumBodyViewportHeight: CGFloat = 56
    /// Reply input row plus the stack spacing above it.
    private static let replyFieldHeight: CGFloat = 45
    /// SwiftUI controls consume slightly more height than AppKit text metrics report.
    private static let controlLayoutReserve: CGFloat = 24

    static func expandedHeight(
        for message: OptionMessage,
        width: CGFloat = AppConstants.Island.width
    ) -> CGFloat {
        let contentWidth = width - contentHorizontalPadding
        let bodyHeight = max(
            minimumBodyViewportHeight,
            textHeight(
                message.body,
                font: .systemFont(ofSize: 15, weight: .semibold),
                width: contentWidth
            )
        )
        let optionWidth = contentWidth - optionTextChrome
        let optionHeights = message.options.map { option in
            let mediaHeight = hasMedia(for: option, in: message) ? optionMediaHeight : 0
            return max(
                minimumOptionHeight,
                max(
                    mediaHeight,
                    textHeight(option, font: .systemFont(ofSize: 13, weight: .medium), width: optionWidth)
                )
                    + optionVerticalPadding
            )
        }
        let gaps = CGFloat(max(optionHeights.count - 1, 0)) * optionSpacing
        let optionsHeight: CGFloat = optionHeights.reduce(0, +) + gaps
        let chrome: CGFloat = verticalChrome + replyFieldHeight + controlLayoutReserve
        return ceil(chrome + bodyHeight + optionsHeight)
    }

    private static func textHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return ceil(bounds.height)
    }

    private static func hasMedia(for option: String, in message: OptionMessage) -> Bool {
        let normalizedOption = option.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.metadata?.optionMedia.contains {
            $0.label.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedOption
        } == true
    }
}
