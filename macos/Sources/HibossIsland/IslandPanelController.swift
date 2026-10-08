// Presents option messages as either a top-edge island or standard window.
// Exports: IslandPanelController driven by flow and presentation settings.
// Dependencies: AppKit windows, SwiftUI hosting, Combine, AttentionReplyState, and app constants.

import AppKit
import HibossKit
import Combine
import SwiftUI

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

@MainActor
final class IslandPanelController {
    let panel: NSPanel
    let optionWindow: NSWindow
    private let flow: OptionFlowStore
    /// One reply state for both hosting roots: drafts survive question and presentation changes.
    let reply = AttentionReplyState()
    private let settings: AppSettings
    private let soundPlayer: any SoundPlaying
    private let screens: () -> [IslandGeometry]
    private let pointerLocation: () -> NSPoint
    private var questionScreen: IslandGeometry?
    private var cancellables: Set<AnyCancellable> = []
    private(set) var dropReveal: IslandDropRevealController?

    init(
        flow: OptionFlowStore,
        settings: AppSettings,
        soundPlayer: any SoundPlaying = SystemSoundPlayer(),
        screens: @escaping () -> [IslandGeometry] = { NSScreen.screens.map(\.islandGeometry) },
        pointerLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation }
    ) {
        self.flow = flow
        self.settings = settings
        self.soundPlayer = soundPlayer
        self.screens = screens
        self.pointerLocation = pointerLocation
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

    /// The surface is always black, so system-drawn parts — caret, selection, placeholders —
    /// must render for dark regardless of the user's system appearance.
    private func configurePanel() {
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        let host = BoxDropHostingView(rootView: IslandView(flow: flow, reply: reply), settings: settings)
        host.sizingOptions = []
        panel.contentView = host
        dropReveal = IslandDropRevealController(
            panel: panel, host: host, pointerLocation: pointerLocation, screens: screens,
            screenDidChange: { [weak self] geometry in
                self?.updateGeometry(geometry, followingPointer: true)
            }
        )
    }

    /// The rounded surface is drawn in SwiftUI, so the window itself must be transparent.
    /// An opaque window would paint its square darkAqua backdrop outside that rounding —
    /// black square corners poking past the panel's bottom edge. The titlebar stays in the
    /// style mask (borderless windows cannot become key) but is hidden and made see-through,
    /// leaving the panel draggable by its background and able to focus the reply field.
    private func configureWindow() {
        optionWindow.appearance = NSAppearance(named: .darkAqua)
        optionWindow.title = L("HiBoss Options")
        optionWindow.isReleasedWhenClosed = false
        optionWindow.level = .floating
        optionWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        optionWindow.minSize = NSSize(width: AppConstants.Island.width, height: 180)
        optionWindow.styleMask.insert(.fullSizeContentView)
        optionWindow.titlebarAppearsTransparent = true
        optionWindow.titleVisibility = .hidden
        optionWindow.backgroundColor = .clear
        optionWindow.isOpaque = false
        optionWindow.hasShadow = true
        optionWindow.isMovableByWindowBackground = true
        for button in Self.titlebarButtons {
            optionWindow.standardWindowButton(button)?.isHidden = true
        }
        let host = NSHostingView(
            rootView: IslandView(flow: flow, reply: reply, surfaceStyle: .window)
        )
        host.sizingOptions = []
        optionWindow.contentView = host
    }

    /// Dismissal lives on the panel's own close control, so the traffic lights would only
    /// draw a second, differently-shaped affordance over the rounded surface.
    private static let titlebarButtons: [NSWindow.ButtonType] = [
        .closeButton, .miniaturizeButton, .zoomButton,
    ]

    private func observeFlow() {
        Publishers.CombineLatest(flow.$activeMessage, settings.$presentationMode)
            .sink { [weak self] message, mode in
                self?.updatePresentation(message: message, mode: mode)
            }
            .store(in: &cancellables)

        // activeMessage publishes once per question reaching the panel — including the ones
        // that surface from the queue behind a skip — and nil when it clears.
        flow.$activeMessage
            .sink { [weak self] message in
                guard message != nil else { return }
                self?.announce()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)
    }

    private func announce() {
        guard settings.playsSound else { return }
        soundPlayer.play(settings.alertSound)
    }

    private func updatePresentation(
        message: OptionMessage?,
        mode: OptionPresentationMode
    ) {
        if message == nil { questionScreen = nil }
        dropReveal?.setPresentation(island: mode == .island, question: message != nil)
        guard let message else {
            if let geometry = targetScreen { setContentInset(geometry.expandedTopInset) }
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
        guard let geometry = targetScreen else { return }
        questionScreen = geometry
        setContentInset(geometry.expandedTopInset)
        let expanded = geometry.expandedFrame(contentHeight: OptionPanelLayout.expandedHeight(for: message))
        panel.setFrame(geometry.collapsedFrame, display: false)
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

    private func reposition() {
        guard settings.presentationMode == .island else { return }
        dropReveal?.refreshPointer()
        if let geometry = targetScreen { updateGeometry(geometry) }
    }

    private func updateGeometry(_ geometry: IslandGeometry, followingPointer: Bool = false) {
        guard settings.presentationMode == .island,
            !followingPointer || questionScreen == nil else { return }
        setContentInset(geometry.expandedTopInset)
        guard let message = flow.activeMessage else { return }
        questionScreen = geometry
        panel.setFrame(
            geometry.expandedFrame(contentHeight: OptionPanelLayout.expandedHeight(for: message)),
            display: true
        )
    }

    private func setContentInset(_ inset: CGFloat) {
        guard let host = panel.contentView as? BoxDropHostingView,
            host.rootView.topInset != inset else { return }
        host.rootView.topInset = inset
    }

    private var targetScreen: IslandGeometry? {
        let available = screens()
        if let questionScreen {
            return available.first(where: {
                if let id = questionScreen.displayID { return $0.displayID == id }
                return $0.screenFrame.origin == questionScreen.screenFrame.origin
            }) ?? available.first
        }
        return available.first(where: { $0.screenFrame.contains(pointerLocation()) }) ?? available.first
    }

    private func expandedHeight(for message: OptionMessage) -> CGFloat {
        let desiredHeight = OptionPanelLayout.expandedHeight(for: message)
        guard let screen = targetScreen else { return desiredHeight }
        return min(desiredHeight, screen.visibleFrame.height * 0.8)
    }
}

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

extension NSScreen {
    var islandGeometry: IslandGeometry {
        IslandGeometry(
            screenFrame: frame, visibleFrame: visibleFrame, safeAreaTop: safeAreaInsets.top,
            auxiliaryTopLeftArea: auxiliaryTopLeftArea, auxiliaryTopRightArea: auxiliaryTopRightArea,
            displayID: (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        )
    }
}
