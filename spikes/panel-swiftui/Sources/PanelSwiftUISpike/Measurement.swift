// Non-interactive hidden-window benchmark for fixture mount, updates, and footprint.
// Exports: MeasurementRunner and percentile().
// Dependencies: AppKit hosting, PanelStore, PanelRootView, Foundation, and Mach footprint.

import AppKit
import SwiftUI

@MainActor
final class MeasurementRunner {
    private static let interactiveTimeout: TimeInterval = 2
    private let names = FixtureLoader.names
    private var index = 0
    private var window: NSWindow?
    private var measurements: [FixtureMeasurement] = []
    private var current: FixtureMeasurement?
    private var mountStart: UInt64 = 0
    private var pendingUpdateStart: UInt64?
    private var updateNumber = 0
    private var store: PanelStore?

    func run() {
        mountNext()
    }

    nonisolated static func printNotMeasured(reason: String) {
        for name in FixtureLoader.names {
            print("fixture=\(name)")
            print("measurement_status=not measured (\(reason))")
            print("cold_mount_ms=not measured")
            print("footprint_before_bytes=not measured")
            print("footprint_after_bytes=not measured")
            print("apply_samples=0")
            print("apply_p50_ms=not measured")
            print("apply_p95_ms=not measured")
        }
    }

    private func mountNext() {
        guard index < names.count else { finish(); return }
        let fixtureName = names[index]
        do {
            let fixture = try FixtureLoader.load(name: fixtureName)
            let store = PanelStore(fixture: fixture)
            self.store = store
            current = FixtureMeasurement(name: fixtureName, beforeBytes: processFootprintBytes())
            mountStart = DispatchTime.now().uptimeNanoseconds
            let root = PanelRootView(spec: fixture.activeSpec ?? .init(root: "", elements: [:]), store: store, onInteractive: { [weak self] in self?.panelBecameInteractive() }, onRevisionApplied: { [weak self] in self?.updateWasApplied() })
            let host = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520), styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            window.isReleasedWhenClosed = false
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            self.window = window
            window.makeKeyAndOrderFront(nil)
            window.displayIfNeeded()
            host.layoutSubtreeIfNeeded()
            DispatchQueue.main.async { [weak self] in self?.panelBecameInteractive() }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.interactiveTimeout) { [weak self] in
                self?.measurementTimedOut(name: fixtureName)
            }
            index += 1
        } catch {
            print("fixture=\(names[index]) error=\(error.localizedDescription)")
            index += 1
            mountNext()
        }
    }

    private func panelBecameInteractive() {
        guard let current else { return }
        current.coldMountMs = elapsedMs(since: mountStart)
        current.afterBytes = processFootprintBytes()
        self.current = current
        scheduleUpdate()
    }

    private func measurementTimedOut(name: String) {
        guard current?.name == name, current?.coldMountMs == nil else { return }
        finishFixture()
    }

    private func scheduleUpdate() {
        guard let store else { return }
        guard updateNumber < 200 else { finishFixture(); return }
        updateNumber += 1
        pendingUpdateStart = DispatchTime.now().uptimeNanoseconds
        let path = index == 1 ? "/task/completed" : "/form/trafficPercent"
        let value: JSONValue = index == 1 ? .number(Double(updateNumber)) : .number(Double((updateNumber % 100) + 1))
        store.applyHostDelta(path: path, value: value)
    }

    private func updateWasApplied() {
        guard pendingUpdateStart != nil else { return }
        current?.applyMs.append(elapsedMs(since: pendingUpdateStart!))
        pendingUpdateStart = nil
        DispatchQueue.main.async { [weak self] in self?.scheduleUpdate() }
    }

    private func finishFixture() {
        if let current { measurements.append(current) }
        current = nil
        updateNumber = 0
        pendingUpdateStart = nil
        window?.close()
        window = nil
        store = nil
        mountNext()
    }

    private func finish() {
        for measurement in measurements { measurement.printReport() }
        NSApp.terminate(nil)
    }

    private func elapsedMs(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }
}

@MainActor
private final class FixtureMeasurement {
    let name: String
    let beforeBytes: UInt64?
    var coldMountMs: Double?
    var afterBytes: UInt64?
    var applyMs: [Double] = []

    init(name: String, beforeBytes: UInt64?) {
        self.name = name
        self.beforeBytes = beforeBytes
    }

    func printReport() {
        print("fixture=\(name)")
        print("cold_mount_ms=\(coldMountMs.map { String(format: "%.3f", $0) } ?? "not measured")")
        print("footprint_before_bytes=\(beforeBytes.map(String.init) ?? "not measured")")
        print("footprint_after_bytes=\(afterBytes.map(String.init) ?? "not measured")")
        for (index, sample) in applyMs.enumerated() { print("apply_ms[\(index + 1)]=\(String(format: "%.3f", sample))") }
        print("apply_samples=\(applyMs.count)")
        print("apply_p50_ms=\(percentile(applyMs, rank: 0.50).map { String(format: "%.3f", $0) } ?? "not measured")")
        print("apply_p95_ms=\(percentile(applyMs, rank: 0.95).map { String(format: "%.3f", $0) } ?? "not measured")")
    }
}

func percentile(_ samples: [Double], rank: Double) -> Double? {
    guard !samples.isEmpty else { return nil }
    let sorted = samples.sorted()
    let position = Double(sorted.count - 1) * rank
    let lower = Int(position.rounded(.down))
    let upper = Int(position.rounded(.up))
    guard lower != upper else { return sorted[lower] }
    return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
}
