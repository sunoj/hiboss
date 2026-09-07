// Repeatable observations for scroll, sizing, keyboard traversal, and live draft state.
// Exports: runSeamProbe(session:).
// Dependencies: AppKit, WebKit, SeamSession, PanelStore, and WebLeafModel.

import AppKit
import CoreGraphics
import WebKit

@MainActor
func runSeamProbe(session: SeamSession) {
    session.store.applyHostDelta(path: "/form/strategy", value: .string("full"))
    session.store.applyHostDelta(path: "/form/trafficPercent", value: .number(80))
    session.append("draft_before_kill=\(session.store.draftDescription())")
    session.append("appearance_native_initial=\(session.targetWindow?.effectiveAppearance.name.rawValue ?? "unknown")")
    session.append("voiceover=not observed")
    scheduleHeightProbe(session: session)
}

@MainActor
private func scheduleHeightProbe(session: SeamSession) {
    guard session.webModel.messageCount > 0 else {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { scheduleHeightProbe(session: session) }
        return
    }
    session.webModel.applyChartHeight(360, sequence: 1)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
        session.webModel.applyChartHeight(150, sequence: 2)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let heights = session.webModel.heightHistory.map { String(format: "%.0f", $0) }.joined(separator: ",")
            session.append("height_callbacks=\(heights)")
            session.append("height_result=\(heightResult(session.webModel.heightHistory))")
            observeScroll(session: session)
            observeKeyViews(session: session)
            session.append("probe_ready=1")
        }
    }
}

@MainActor
private func heightResult(_ history: [CGFloat]) -> String {
    guard let first = history.first, let last = history.last else { return "not observed" }
    let oscillating = history.count > 4 && history.dropFirst().dropLast().contains { abs($0 - first) < 1 && abs($0 - last) > 1 }
    if oscillating { return "oscillated" }
    if last < 48 { return "clipped" }
    guard let peak = history.max() else { return "not observed" }
    return last < peak - 20 ? "settled" : "not settled"
}

@MainActor
private func observeScroll(session: SeamSession) {
    guard let window = session.targetWindow, let webView = findWebView(in: window.contentView) else { session.append("scroll=not observed (web leaf view unavailable)"); return }
    let before = scrollOffsets(in: window.contentView)
    let point = webView.convert(NSPoint(x: webView.bounds.midX, y: webView.bounds.midY), to: window.contentView)
    let screenPoint = window.convertToScreen(NSRect(origin: point, size: .zero)).origin
    if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -160, wheel2: 0, wheel3: 0) {
        event.location = CGPoint(x: screenPoint.x, y: screenPoint.y)
        event.post(tap: .cghidEventTap)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
        let after = scrollOffsets(in: window.contentView)
        session.append("scroll_synthetic_over_chart=\(scrollResult(before: before, after: after))")
        session.append("scroll_offsets_before=\(before)")
        session.append("scroll_offsets_after=\(after)")
    }
}

@MainActor
private func scrollResult(before: [String], after: [String]) -> String {
    if before == after { return "nothing" }
    let changed = zip(before, after).filter { $0.0 != $0.1 }.map(\.1)
    return changed.contains(where: { $0.contains("WK") }) ? "chart" : "page"
}

@MainActor
private func observeKeyViews(session: SeamSession) {
    guard let window = session.targetWindow else { session.append("tab_forward=not observed (window unavailable)"); return }
    window.makeKeyAndOrderFront(nil)
    var forward: [String] = []
    for _ in 0..<5 { window.selectNextKeyView(nil); forward.append(keyViewName(window.firstResponder)) }
    var backward: [String] = []
    for _ in 0..<5 { window.selectPreviousKeyView(nil); backward.append(keyViewName(window.firstResponder)) }
    session.append("tab_forward=\(forward.joined(separator: ">"))")
    session.append("tab_backward=\(backward.joined(separator: ">"))")
    session.append("focus_ring=not observed (requires a person watching the window)")
}

@MainActor
private func keyViewName(_ responder: NSResponder?) -> String {
    guard let view = responder as? NSView else { return String(describing: type(of: responder)) }
    if let editor = view as? NSTextView, let delegate = editor.delegate as? NSView { return keyViewName(delegate) }
    if let control = view as? NSButton, !control.title.isEmpty { return "native:\(control.title)" }
    if let control = view as? NSControl, !control.stringValue.isEmpty { return "native:\(control.stringValue)" }
    var current: NSView? = view
    while let candidate = current {
        let identifier = candidate.accessibilityIdentifier()
        if !identifier.isEmpty { return identifier }
        if candidate is WKWebView { return "web-leaf" }
        current = candidate.superview
    }
    return String(describing: type(of: view))
}

@MainActor
private func findWebView(in view: NSView?) -> WKWebView? {
    guard let view else { return nil }
    if let webView = view as? WKWebView { return webView }
    for child in view.subviews { if let webView = findWebView(in: child) { return webView } }
    return nil
}

@MainActor
private func scrollOffsets(in view: NSView?) -> [String] {
    guard let view else { return [] }
    var result: [String] = []
    if let scroll = view as? NSScrollView { result.append("\(type(of: scroll))=\(Int(scroll.contentView.bounds.origin.y))") }
    for child in view.subviews { result += scrollOffsets(in: child) }
    return result
}

@MainActor
private extension NSView {
    var enclosingWebView: WKWebView? {
        var current: NSView? = superview
        while let view = current { if let web = view as? WKWebView { return web }; current = view.superview }
        return nil
    }
}
