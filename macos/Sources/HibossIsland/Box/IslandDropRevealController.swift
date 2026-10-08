// Observes mouse events to reveal an ordered-out Island without intercepting input.
// Exports IslandDropRevealController, using one-shot dwell and hide deadlines.
// Dependencies: AppKit, IslandDropRevealPolicy and BoxDropHostingView.

import AppKit
import HibossKit

@MainActor
final class IslandDropRevealController {
    private let panel: NSPanel
    private let pointerLocation: () -> NSPoint
    private let screens: () -> [IslandGeometry]
    private let screenDidChange: (IslandGeometry) -> Void
    private var policy = IslandDropRevealPolicy()
    private var monitors: [Any] = []
    private var pending: DispatchWorkItem?
    private var scheduledDeadline: TimeInterval?
    private var geometry: IslandGeometry?
    private var pointerIsInside = false

    init(
        panel: NSPanel,
        host: BoxDropHostingView,
        pointerLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation },
        screens: @escaping () -> [IslandGeometry] = { NSScreen.screens.map(\.islandGeometry) },
        screenDidChange: @escaping (IslandGeometry) -> Void = { _ in }
    ) {
        self.panel = panel
        self.pointerLocation = pointerLocation
        self.screens = screens
        self.screenDidChange = screenDidChange
        panel.acceptsMouseMovedEvents = true
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.pointerMoved(to: pointerLocation(), dragging: event.type == .leftMouseDragged)
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.pointerMoved(to: pointerLocation(), dragging: event.type == .leftMouseDragged)
            return event
        }) { monitors.append(local) }
        host.activityDidChange = { [weak self] popover, uploading in
            self?.send(.activity(popover: popover, uploading: uploading))
        }
    }

    isolated deinit {
        pending?.cancel()
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
    }

    func setPresentation(island: Bool, question: Bool) {
        send(.presentation(island: island, question: question))
    }

    func refreshPointer() {
        pointerMoved(to: pointerLocation(), dragging: false)
    }

    static func hotZone(on screen: NSRect) -> NSRect {
        IslandGeometry(screenFrame: screen).hotZone
    }

    func pointerMoved(to point: NSPoint, dragging: Bool) {
        let target = screens().first { $0.screenFrame.contains(point) }
        pointerIsInside = false
        if geometry != target {
            send(.pointer(inHotZone: false, dragging: false))
            geometry = target
            if let target { screenDidChange(target) }
        }
        pointerIsInside = target?.hotZone.contains(point) == true
        send(.pointer(inHotZone: pointerIsInside, dragging: dragging))
    }

    private func send(_ event: IslandDropRevealPolicy.Event) {
        let before = policy.visibility
        policy.send(event, at: ProcessInfo.processInfo.systemUptime)
        switch policy.visibility {
        case .hidden:
            if panel.isVisible { panel.orderOut(nil) }
        case .dropTarget:
            if let geometry,
                before != .dropTarget || (panel.frame != geometry.collapsedFrame && pointerIsInside) {
                showDropTarget(in: geometry.collapsedFrame)
            }
        case .question:
            break
        }
        scheduleDeadline()
    }

    private func showDropTarget(in frame: NSRect) {
        let wasVisible = panel.isVisible
        panel.setFrame(frame, display: false)
        if !wasVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = AppConstants.Island.animationDuration * 0.7
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 1
        }
    }

    private func scheduleDeadline() {
        guard scheduledDeadline != policy.nextDeadline else { return }
        pending?.cancel()
        pending = nil
        scheduledDeadline = policy.nextDeadline
        guard let deadline = scheduledDeadline else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil
            self.scheduledDeadline = nil
            self.refreshPointer()
            self.send(.deadline)
        }
        pending = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0, deadline - ProcessInfo.processInfo.systemUptime), execute: work
        )
    }
}
