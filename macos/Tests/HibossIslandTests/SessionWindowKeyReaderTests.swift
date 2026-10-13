// Verifies the production key-state observer reads its hosting NSWindow's actual property.
// Exports: SessionWindowKeyReaderTests covering attachment, unrelated notifications, and detachment.
// Dependencies: AppKit, XCTest, and the same KeyView used by the default workspace binding.

import AppKit
import XCTest
@testable import HibossIsland

@MainActor
final class SessionWindowKeyReaderTests: XCTestCase {
    func testProductionReaderUsesRealHostingWindowStateAndIgnoresOtherWindows() async throws {
        _ = NSApplication.shared
        var readings: [Bool] = []
        let reader = SessionWindowKeyReader.KeyView { readings.append($0) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = reader
        try await waitForCondition { !readings.isEmpty }
        XCTAssertTrue(reader.window === window)
        XCTAssertEqual(readings.last, window.isKeyWindow)
        let count = readings.count
        let other = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { other.close() }
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: other)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(readings.count, count)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        try await waitForCondition { readings.count > count }
        XCTAssertEqual(readings.last, window.isKeyWindow, "The notification name cannot imply key state")
        let attachedCount = readings.count
        window.contentView = nil
        try await waitForCondition { readings.count > attachedCount }
        XCTAssertNil(reader.window)
        XCTAssertEqual(readings.last, false)
    }
}
