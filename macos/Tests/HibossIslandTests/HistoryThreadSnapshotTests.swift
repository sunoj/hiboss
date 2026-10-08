// Renders every History thread outcome in both system appearances.
// Exports: HistoryThreadSnapshotTests; HIBOSS_SNAPSHOT_DIR writes inspectable PNGs.
// Dependencies: AppKit, SwiftUI ImageRenderer, HibossKit, and HistoryThreadRow.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class HistoryThreadSnapshotTests: XCTestCase {
    private var imageBaseURL = ""

    func testEveryOutcomeInLightAndDark() async throws {
        _ = NSApplication.shared
        let media = HistorySnapshotMediaServer()
        defer { media.stop() }
        try await media.start()
        imageBaseURL = media.baseURL
        for (name, thread, expected) in fixtures {
            XCTAssertEqual(thread.outcome, expected, name)
            for scheme in [ColorScheme.light, .dark] {
                let bitmap = try render(thread, scheme: scheme)
                XCTAssertEqual(bitmap.pixelsWide, 1_280)
                XCTAssertGreaterThan(bitmap.pixelsHigh, 180)
                XCTAssertLessThan(bitmap.pixelsHigh, 1_600)
                try write(bitmap, name: "\(name)-\(scheme == .light ? "light" : "dark")")
                let native = try await renderNative(thread, scheme: scheme)
                try write(native, name: "\(name)-\(scheme == .light ? "light" : "dark")-native")
            }
        }
    }

    private func renderNative(_ thread: MessageThread, scheme: ColorScheme) async throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView:
            HistoryThreadRow(thread: thread, reply: AttentionReplyState(),
                isExpanded: .constant(true), isSearching: false, onCollapse: {}, onChoose: { _ in nil })
                .padding(.horizontal, 24).frame(width: 640).fixedSize(horizontal: false, vertical: true)
                .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, scheme))
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 640, height: 800),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await waitForCondition { host.fittingSize.height > 100 }
        window.setContentSize(host.fittingSize)
        XCTAssertEqual(host.bounds.height, host.fittingSize.height, accuracy: 1,
            "Native host height for \(thread.id): \(host.bounds) / \(host.fittingSize)")
        host.layoutSubtreeIfNeeded()
        if !(thread.message.metadata?.optionMedia.isEmpty ?? true) {
            try await waitForCondition { self.thumbnailLoaded(host) }
        }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    private func thumbnailLoaded(_ host: NSView) -> Bool {
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return false }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        guard let color = bitmap.colorAt(x: Int(120 * scale), y: Int(130 * scale))?
            .usingColorSpace(.deviceRGB) else { return false }
        let components = [color.redComponent, color.greenComponent, color.blueComponent]
        return (components.max() ?? 0) - (components.min() ?? 0) > 0.1
    }

    private func render(_ thread: MessageThread, scheme: ColorScheme) throws -> NSBitmapImageRep {
        let appearance = try XCTUnwrap(NSAppearance(named: scheme == .light ? .aqua : .darkAqua))
        var rendered: NSImage?
        appearance.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content:
                HistoryThreadRow(thread: thread, reply: AttentionReplyState(),
                    isExpanded: .constant(true), isSearching: false, onCollapse: {}, onChoose: { _ in nil })
                    .padding(.horizontal, 24).frame(width: 640)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, scheme)
            )
            renderer.scale = 2
            rendered = renderer.nsImage
        }
        return try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(rendered?.tiffRepresentation)))
    }

    private func write(_ bitmap: NSBitmapImageRep, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["HIBOSS_SNAPSHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url.appendingPathComponent("\(name).png"))
    }

    private var fixtures: [(String, MessageThread, ThreadOutcome)] {
        let text = question()
        let images = question(images: true)
        return [
            ("open-text", MessageThread(message: text), .open),
            ("open-images", MessageThread(message: images), .open),
            ("chosen", MessageThread(message: text, replies: [answer("Ship")]),
                .chosen(option: "Ship", source: "telegram")),
            ("chosen-image", MessageThread(message: images, replies: [answer("Ship")]),
                .chosen(option: "Ship", source: "telegram")),
            ("auto-selected", MessageThread(message: text, replies: [answer("Hold", automatic: true)]),
                .autoSelected(option: "Hold")),
            ("replied-free-text", MessageThread(message: text, replies: [
                answer("Check the migration first.", id: "older", at: "2026-10-08T10:01:00Z"),
                answer("Wait until the rollback has been verified.", id: "newer")]),
                .replied(text: "Wait until the rollback has been verified.", source: "telegram")),
            ("expired", MessageThread(message: question(status: "expired")), .expired),
            ("standalone-boss", MessageThread(message: answer("Please investigate the slow query.")), .none),
            ("plain-with-reply", MessageThread(message: question(options: []),
                replies: [answer("Thanks, the report looks good.")]), .none)
        ]
    }

    private func question(
        images: Bool = false, status: String = "delivered", options: [String] = ["Ship", "Hold"]
    ) -> HistoryMessage {
        let media = images ? [
            OptionMedia(label: "Ship", url: "\(imageBaseURL)/ship.png",
                caption: "Release preview with the updated navigation."),
            OptionMedia(label: "Hold", url: "\(imageBaseURL)/hold.png",
                caption: "Keep the current layout for another review.")
        ] : []
        return HistoryMessage(id: "question", body: options.isEmpty
            ? "The deployment report is ready. All checks passed."
            : "The release is ready. Which plan should we use?",
            agentName: "Build Agent", direction: "agent_to_boss", status: status, priority: "high",
            metadata: MessageMetadata(options: options, optionMedia: media, defaultOption: "Hold"),
            expiresAt: status == "expired" || options.isEmpty ? nil
                : ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(300)),
            createdAt: "2026-10-08T10:00:00Z", sessionId: "session")
    }

    private func answer(
        _ text: String, automatic: Bool = false, id: MessageID = "reply", at: String = "2026-10-08T10:02:00Z"
    ) -> HistoryMessage {
        HistoryMessage(id: id, body: text, agentName: "Build Agent", direction: "boss_to_agent",
            status: "sent", priority: "normal", replyTo: "question",
            metadata: MessageMetadata(options: [], source: "telegram", isAutoDefault: automatic),
            createdAt: at, targetSessionId: "session")
    }
}
