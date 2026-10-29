// Animates expiry strokes in the compositor without invalidating SwiftUI layout.
// Exports: ExpiryBandLayer and its native ExpiryBandView.
// Dependencies: AppKit, QuartzCore, SwiftUI, and ExpiryProgress.

import AppKit
import QuartzCore
import SwiftUI

struct ExpiryBandLayer: NSViewRepresentable {
    let progress: ExpiryProgress
    let surfaceStyle: OptionSurfaceStyle

    func makeNSView(context: Context) -> ExpiryBandView {
        ExpiryBandView(progress: progress, surfaceStyle: surfaceStyle)
    }

    func updateNSView(_ view: ExpiryBandView, context: Context) {
        guard view.progress != progress || view.surfaceStyle != surfaceStyle else { return }
        view.progress = progress
        view.surfaceStyle = surfaceStyle
        view.needsLayout = true
        view.resynchronize()
    }
}

final class ExpiryBandView: NSView {
    var progress: ExpiryProgress
    var surfaceStyle: OptionSurfaceStyle
    let stroke = CAShapeLayer()
    private var timer: Timer?

    override var isFlipped: Bool { true }

    init(progress: ExpiryProgress, surfaceStyle: OptionSurfaceStyle) {
        self.progress = progress
        self.surfaceStyle = surfaceStyle
        super.init(frame: .zero)
        wantsLayer = true
        stroke.fillColor = nil
        stroke.lineWidth = 1
        stroke.lineCap = .round
        stroke.shadowOpacity = 0.7
        stroke.shadowRadius = 2.5
        stroke.shadowOffset = .zero
        layer?.addSublayer(stroke)
        for name in [NSApplication.didBecomeActiveNotification, NSWindow.didChangeOcclusionStateNotification,
                     Notification.Name("NSSystemClockDidChangeNotification")] {
            NotificationCenter.default.addObserver(self, selector: #selector(resynchronize), name: name,
                object: nil)
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(resynchronize),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate()
        timer = nil
        guard window != nil else { return }
        // Bound media-time drift even when the wall clock changes without a notification.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            MainActor.assumeIsolated { self.resynchronize() }
        }
        resynchronize()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        resynchronize()
    }

    override func layout() {
        super.layout()
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stroke.frame = bounds
        switch surfaceStyle {
        case .island: stroke.path = IslandBandPath(bottomRadius: 24).path(in: rect).cgPath
        case .window:
            stroke.path = RoundedRectangle(cornerRadius: 18, style: .continuous).path(in: rect).cgPath
        }
        CATransaction.commit()
        resynchronize()
    }

    @objc func resynchronize() {
        let now = Date()
        let remaining = progress.expiresAt.timeIntervalSince(now)
        let color = color(for: progress.urgency(at: now))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stroke.removeAllAnimations()
        // The model holds the current value so captures and a lapsed animation show it too.
        stroke.strokeEnd = max(0, progress.fraction(at: now))
        stroke.strokeColor = color
        stroke.shadowColor = color
        if remaining > 0 {
            let drain = CABasicAnimation(keyPath: "strokeEnd")
            drain.fromValue = progress.fraction(at: now)
            drain.toValue = 0
            drain.duration = remaining
            drain.timingFunction = CAMediaTimingFunction(name: .linear)
            stroke.add(drain, forKey: "drain")
            animateColors(now: now, remaining: remaining)
        }
        CATransaction.commit()
    }

    private func animateColors(now: Date, remaining: TimeInterval) {
        let total = progress.expiresAt.timeIntervalSince(progress.startedAt)
        var colors = [color(for: progress.urgency(at: now))]
        var times: [NSNumber] = [0]
        for fraction in [ExpiryProgress.cautionFraction, ExpiryProgress.urgentFraction] {
            let delay = remaining - total * fraction
            guard delay > 0, delay < remaining else { continue }
            times.append(NSNumber(value: delay / remaining))
            colors.append(color(for: fraction == ExpiryProgress.cautionFraction ? .caution : .urgent))
        }
        times.append(1)
        colors.append(color(for: .urgent))
        for key in ["strokeColor", "shadowColor"] {
            let animation = CAKeyframeAnimation(keyPath: key)
            animation.values = colors
            animation.keyTimes = times
            animation.calculationMode = .discrete
            animation.duration = remaining
            stroke.add(animation, forKey: key)
        }
    }

    private func color(for urgency: ExpiryProgress.Urgency) -> CGColor {
        let color: Color = switch urgency {
        case .calm: .green
        case .caution: .orange
        case .urgent: .red
        }
        return NSColor(color).cgColor
    }
}
