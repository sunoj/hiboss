// CPU measurements for opt-in real-window performance surveys; no cost assertions.
// Exports: PerfSurveyMetrics with process and main-thread CPU clocks and Markdown rows.
// Dependencies: Darwin, AppKit, XCTest; deferred SwiftUI work is included in a fixed drain window.

import AppKit
import Darwin
import XCTest

@MainActor
enum PerfSurveyMetrics {
    static func enabled() throws {
        guard ProcessInfo.processInfo.environment["HIBOSS_PERF_SURVEY"] == "1" else {
            throw XCTSkip("Desktop performance survey runs only through scripts/perf-survey.sh")
        }
    }

    static func accepts(_ name: String) -> Bool {
        let filter = ProcessInfo.processInfo.environment["HIBOSS_PERF_FILTER"] ?? ""
        return filter.isEmpty || filter.split(separator: ",").contains {
            name.localizedCaseInsensitiveContains(String($0))
        }
    }

    static func processCPU() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return [usage.ru_utime, usage.ru_stime].reduce(0) {
            $0 + Double($1.tv_sec) + Double($1.tv_usec) / 1_000_000
        }
    }

    static func mainCPU() -> Double {
        precondition(Thread.isMainThread)
        var time = timespec()
        precondition(clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time) == 0)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
    }

    static func action(_ window: NSWindow, perform: () async throws -> Void) async throws -> Double {
        let start = mainCPU()
        try await perform()
        // Include queued body evaluation, layout and drawing, without counting sleep as CPU.
        try await Task.sleep(for: .milliseconds(300))
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return (mainCPU() - start) * 1_000
    }

    static func measure(_ name: String, size: String, window: NSWindow,
                        update: () async throws -> Void,
                        interact: (() async throws -> Void)? = nil) async throws {
        let settling = max(1, Double(ProcessInfo.processInfo.environment[
            "HIBOSS_PERF_SETTLE_SECONDS"] ?? "1") ?? 1)
        try await Task.sleep(for: .seconds(settling))
        let start = processCPU()
        let wall = ProcessInfo.processInfo.systemUptime
        try await Task.sleep(for: .seconds(3))
        let idle = 100 * (processCPU() - start) / (ProcessInfo.processInfo.systemUptime - wall)
        let updateMS = try await action(window, perform: update)
        try await profile(name, window: window, update: update)
        let scroll = try await scrollStep(window)
        var interaction: Double?
        if let interact { interaction = try await action(window, perform: interact) }
        let config = ProcessInfo.processInfo.environment["HIBOSS_PERF_CONFIG"] ?? "unspecified"
        let commit = ProcessInfo.processInfo.environment["HIBOSS_PERF_COMMIT"] ?? "unspecified"
        let frame = window.contentView?.bounds.size ?? .zero
        let data = size + (settling > 1 ? "; settle \(number(settling))s" : "")
        print("PERF | \(name) | \(data) | \(Int(frame.width))×\(Int(frame.height)) | "
            + "\(number(idle)) | \(number(updateMS)) | \(number(interaction)) | \(number(scroll)) | "
            + "\(config) | \(commit) |")
    }

    static func number(_ value: Double?) -> String {
        value.map { String(format: "%.2f", $0) } ?? "—"
    }

    static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private static func scrollStep(_ window: NSWindow, delta: CGFloat = 300) async throws -> Double? {
        guard let root = window.contentView,
              let scroll = descendants(root).compactMap({ $0 as? NSScrollView }).last(where: {
                  ($0.documentView?.bounds.height ?? 0) > $0.contentView.bounds.height + 300
              }) else { return nil }
        let before = scroll.contentView.bounds.origin
        let value = try await action(window) {
            scroll.contentView.scroll(to: NSPoint(x: before.x, y: before.y + delta))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        guard scroll.contentView.bounds.origin != before else { return nil }
        return value
    }

    private static func profile(_ name: String, window: NSWindow,
                                update: () async throws -> Void) async throws {
        let env = ProcessInfo.processInfo.environment
        guard let filter = env["HIBOSS_PERF_SAMPLE"], filter.split(separator: ",").contains(where: {
            name.contains(String($0))
        }),
              let directory = env["HIBOSS_PERF_OUTPUT"] else { return }
        try await sample(name + ".idle", directory: directory) {
            try await Task.sleep(for: .seconds(3))
        }
        try await sample(name + ".updates", directory: directory) {
            let end = ProcessInfo.processInfo.systemUptime + 3
            while ProcessInfo.processInfo.systemUptime < end {
                _ = try await action(window, perform: update)
            }
        }
        if name.hasPrefix("Box browser") {
            try await sample(name + ".scroll", directory: directory) {
                let end = ProcessInfo.processInfo.systemUptime + 3
                while ProcessInfo.processInfo.systemUptime < end {
                    _ = try await scrollStep(window)
                    _ = try await scrollStep(window, delta: -300)
                }
            }
        }
    }

    private static func sample(_ name: String, directory: String,
                               during: () async throws -> Void) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        process.arguments = [String(ProcessInfo.processInfo.processIdentifier), "3", "1", "-file",
            directory + "/" + name.replacingOccurrences(of: "/", with: "-") + ".sample.txt"]
        try process.run()
        try await during()
        while process.isRunning { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
