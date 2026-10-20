// Presents option messages as either a top-edge island or standard window.
// Exports: IslandPanelController driven by flow and presentation settings.
// Dependencies: AppKit windows, SwiftUI hosting, Combine, AttentionReplyState, and app constants.

import AppKit
import HibossKit
import Combine
import SwiftUI

@MainActor
final class IslandPanelController {
    let panel: NSPanel
    let optionWindow: NSWindow
    private let flow: OptionFlowStore
    private let attention: IslandAttention
    /// One reply state for both hosting roots: drafts survive question and presentation changes.
    let reply = AttentionReplyState()
    private let settings: AppSettings
    private let soundPlayer: any SoundPlaying
    private let screens: () -> [IslandGeometry]
    let overview: OverviewStore
    private let pointerLocation: () -> NSPoint
    private let activate: () -> Void
    private var questionScreen: IslandGeometry?
    private var pendingPresentation = false
    private(set) var naturalHeight: CGFloat?
    private var presentedID: MessageID?
    private var islandMeasurement: (MessageID, CGFloat)?
    private var windowMeasurement: (MessageID, CGFloat)?
    private var cancellables: Set<AnyCancellable> = []
    private(set) var dropReveal: IslandDropRevealController?

    init(
        flow: OptionFlowStore,
        settings: AppSettings,
        overview: OverviewStore = OverviewStore(),
        soundPlayer: any SoundPlaying = SystemSoundPlayer(),
        screens: @escaping () -> [IslandGeometry] = { NSScreen.screens.map(\.islandGeometry) },
        pointerLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation },
        activate: @escaping () -> Void = { NSApp.activate(ignoringOtherApps: true) },
        attention: IslandAttention = .shared
    ) {
        self.flow = flow
        self.attention = attention
        self.settings = settings
        self.overview = overview
        self.soundPlayer = soundPlayer
        self.screens = screens
        self.pointerLocation = pointerLocation
        self.activate = activate
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
        let host = BoxDropHostingView(
            rootView: IslandView(flow: flow, reply: reply, overview: overview,
                attention: attention, reportHeight: { [weak self] id, height in
                    self?.contentHeightChanged(id: id, height: height, mode: .island)
                }), settings: settings)
        host.sizingOptions = []
        panel.contentView = host
        panel.setContentSize(NSSize(width: AppConstants.Island.width, height: 600))
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
        optionWindow.minSize = NSSize(width: AppConstants.Island.width, height: 1)
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
            rootView: IslandView(flow: flow, reply: reply, overview: overview,
                surfaceStyle: .window, attention: attention, reportHeight: { [weak self] id, height in
                    self?.contentHeightChanged(id: id, height: height, mode: .window)
                })
        )
        host.sizingOptions = []
        // The transparent, hidden titlebar must not reduce the measured content height.
        host.safeAreaRegions = []
        optionWindow.contentView = host
        optionWindow.setContentSize(NSSize(width: AppConstants.Island.width, height: 600))
    }

    /// Dismissal lives on the panel's own close control, so the traffic lights would only
    /// draw a second, differently-shaped affordance over the rounded surface.
    private static let titlebarButtons: [NSWindow.ButtonType] = [
        .closeButton, .miniaturizeButton, .zoomButton,
    ]

    private func observeFlow() {
        let content = Publishers.CombineLatest4(
            overview.$snapshot, flow.$activeMessage, flow.$presentationState,
            attention.$skippedMessageIDs)
        // Use the emitted values: every `@Published` emits before its property changes.
        let presentations = content.map { snapshot, active, state, skipped -> IslandPresentation? in
            IslandAttention.presentation(snapshot: snapshot.today, active: active, state: state,
                skipped: skipped)
        }
        Publishers.CombineLatest(presentations, settings.$presentationMode)
            .removeDuplicates { previous, next in
                previous.0?.message.id == next.0?.message.id
                    && previous.1 == next.1
            }
            .sink { [weak self] presentation, mode in
                self?.updatePresentation(message: presentation?.message, mode: mode)
            }
            .store(in: &cancellables)

        // activeMessage publishes once per question reaching the panel and nil when it clears.
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
        presentedID = message?.id
        pendingPresentation = message != nil
        naturalHeight = nil
        if message == nil { questionScreen = nil }
        dropReveal?.setPresentation(island: mode == .island, question: message != nil)
        guard message != nil else {
            if let geometry = targetScreen { setContentInset(geometry.expandedTopInset) }
            optionWindow.orderOut(nil)
            return
        }
        if mode == .island {
            optionWindow.orderOut(nil)
            questionScreen = targetScreen
            if let geometry = targetScreen { restoreIslandWidth(geometry) }
        } else {
            panel.orderOut(nil)
            restoreWindowWidth()
            activate()
        }
        // Lay out the actual hosting root while ordered out. It reports before first display.
        DispatchQueue.main.async { [weak self] in self?.prepareLiveContent(mode: mode) }
    }

    private func prepareLiveContent(mode: OptionPresentationMode) {
        guard settings.presentationMode == mode, pendingPresentation else { return }
        let window = mode == .island ? panel : optionWindow
        window.contentView?.layoutSubtreeIfNeeded()
        _ = window.contentView?.fittingSize
        let measurement = mode == .island ? islandMeasurement : windowMeasurement
        if let (id, height) = measurement { contentHeightChanged(id: id, height: height, mode: mode) }
    }

    private func contentHeightChanged(id: MessageID, height: CGFloat, mode: OptionPresentationMode) {
        if mode == .island { islandMeasurement = (id, height) }
        else { windowMeasurement = (id, height) }
        // Coalesce reports and defer AppKit mutations until the layout transaction finishes.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.settings.presentationMode == mode else { return }
            let measurement = mode == .island ? self.islandMeasurement : self.windowMeasurement
            guard let (id, height) = measurement, self.presentedID == id else { return }
            guard self.pendingPresentation || self.naturalHeight != height else { return }
            self.naturalHeight = height
            self.applyContentHeight(height, mode: mode)
        }
    }

    private func applyContentHeight(_ height: CGFloat, mode: OptionPresentationMode) {
        let first = pendingPresentation
        pendingPresentation = false
        if mode == .island {
            guard let geometry = targetScreen else { return }
            let frame = geometry.expandedFrame(contentHeight: height)
            if panel.frame != frame { panel.setFrame(frame, display: true) }
            if first {
                panel.alphaValue = 1
                panel.orderFrontRegardless()
            }
        } else {
            let capped = min(height, targetScreen.map { $0.visibleFrame.height * 0.8 } ?? height)
            let size = NSSize(width: AppConstants.Island.width, height: capped)
            if optionWindow.contentView?.frame.size != size { optionWindow.setContentSize(size) }
            if first {
                if !optionWindow.isVisible { optionWindow.center() }
                optionWindow.makeKeyAndOrderFront(nil)
            }
        }
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
        guard presentedID != nil else { return }
        questionScreen = geometry
        if let naturalHeight { applyContentHeight(naturalHeight, mode: .island) }
    }

    func setContentInset(_ inset: CGFloat) {
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
