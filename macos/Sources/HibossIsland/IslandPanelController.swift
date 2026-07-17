// Presents option messages as either a top-edge island or standard window.
// Exports: IslandPanelController driven by flow and presentation settings.
// Dependencies: AppKit windows, SwiftUI hosting, Combine, and app constants.

import AppKit
import Combine
import SwiftUI

enum OptionPanelLayout {
    private static let contentHorizontalPadding: CGFloat = 36
    private static let optionTextChrome: CGFloat = 46
    private static let verticalChrome: CGFloat = 86
    private static let optionVerticalPadding: CGFloat = 18
    private static let optionSpacing: CGFloat = 7
    private static let minimumOptionHeight: CGFloat = 35
    /// Reply input row plus the stack spacing above it.
    private static let replyFieldHeight: CGFloat = 45

    static func expandedHeight(
        for message: OptionMessage,
        width: CGFloat = AppConstants.Island.width
    ) -> CGFloat {
        let contentWidth = width - contentHorizontalPadding
        let bodyHeight = textHeight(
            message.body,
            font: .systemFont(ofSize: 15, weight: .semibold),
            width: contentWidth
        )
        let optionWidth = contentWidth - optionTextChrome
        let optionHeights = message.options.map { option in
            max(
                minimumOptionHeight,
                textHeight(option, font: .systemFont(ofSize: 13, weight: .medium), width: optionWidth)
                    + optionVerticalPadding
            )
        }
        let gaps = CGFloat(max(optionHeights.count - 1, 0)) * optionSpacing
        let optionsHeight: CGFloat = optionHeights.reduce(0, +) + gaps
        let chrome: CGFloat = verticalChrome + replyFieldHeight
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
}

@MainActor
final class IslandPanelController {
    private let panel: IslandPanel
    private let optionWindow: NSWindow
    private let flow: OptionFlowStore
    private let settings: AppSettings
    private var cancellables: Set<AnyCancellable> = []

    init(flow: OptionFlowStore, settings: AppSettings) {
        self.flow = flow
        self.settings = settings
        panel = IslandPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        optionWindow = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        configurePanel()
        configureWindow()
        observeFlow()
    }

    private func configurePanel() {
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.contentView = NSHostingView(rootView: IslandView(flow: flow))
    }

    private func configureWindow() {
        optionWindow.title = "HiBoss Options"
        optionWindow.isReleasedWhenClosed = false
        optionWindow.level = .floating
        optionWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        optionWindow.minSize = NSSize(width: AppConstants.Island.width, height: 180)
        optionWindow.contentView = NSHostingView(
            rootView: IslandView(flow: flow, surfaceStyle: .window)
        )
    }

    private func observeFlow() {
        Publishers.CombineLatest(flow.$activeMessage, settings.$presentationMode)
            .sink { [weak self] message, mode in
                self?.updatePresentation(message: message, mode: mode)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)
    }

    private func updatePresentation(
        message: OptionMessage?,
        mode: OptionPresentationMode
    ) {
        guard let message else {
            hideIsland()
            optionWindow.orderOut(nil)
            return
        }
        switch mode {
        case .island:
            optionWindow.orderOut(nil)
            showIsland(message)
        case .window:
            panel.orderOut(nil)
            showWindow(message)
        }
    }

    private func showIsland(_ message: OptionMessage) {
        let screen = targetScreen
        let height = expandedHeight(for: message)
        let expanded = frame(on: screen, width: AppConstants.Island.width, height: height)
        let collapsed = frame(
            on: screen,
            width: AppConstants.Island.collapsedWidth,
            height: AppConstants.Island.collapsedHeight
        )
        panel.setFrame(collapsed, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = AppConstants.Island.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(expanded, display: true)
            panel.animator().alphaValue = 1
        }
    }

    private func showWindow(_ message: OptionMessage) {
        let wasVisible = optionWindow.isVisible
        let height = max(expandedHeight(for: message), 180)
        optionWindow.setContentSize(NSSize(width: AppConstants.Island.width, height: height))
        if !wasVisible { optionWindow.center() }
        NSApp.activate(ignoringOtherApps: true)
        optionWindow.makeKeyAndOrderFront(nil)
    }

    private func hideIsland() {
        guard panel.isVisible else { return }
        let collapsed = frame(
            on: targetScreen,
            width: AppConstants.Island.collapsedWidth,
            height: AppConstants.Island.collapsedHeight
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = AppConstants.Island.animationDuration * 0.7
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(collapsed, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self,
                      self.flow.activeMessage == nil
                        || self.settings.presentationMode != .island else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    private func reposition() {
        guard settings.presentationMode == .island,
              let message = flow.activeMessage else { return }
        let height = expandedHeight(for: message)
        panel.setFrame(
            frame(on: targetScreen, width: AppConstants.Island.width, height: height),
            display: true
        )
    }

    private var targetScreen: NSScreen {
        NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func expandedHeight(for message: OptionMessage) -> CGFloat {
        let desiredHeight = OptionPanelLayout.expandedHeight(for: message)
        return min(desiredHeight, targetScreen.visibleFrame.height * 0.8)
    }

    private func frame(on screen: NSScreen, width: CGFloat, height: CGFloat) -> NSRect {
        NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }
}

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
