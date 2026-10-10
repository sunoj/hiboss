// Hosts decision controls and status summaries to verify their rendered layout and colours.
// Exports: DecisionPresentationTests for wrapping choices, Ink fill, and zero-count chips.
// Dependencies: AppKit bitmap capture, Vision OCR, SwiftUI, and production Today components.

import AppKit
import HibossKit
import SwiftUI
import XCTest
import Vision
@testable import HibossIsland

@MainActor
final class DecisionPresentationTests: XCTestCase {
    func testChoicesShareARowWrapAndUseInkInBothAppearances() async throws {
        let options = ["Deploy", "Not yet", "Investigate the rollback before proceeding"]
        let message = AttentionTestSupport.ask(id: "choices", options: options)
        let item = AttentionItem(message: message, group: .priority)
        for scheme in [ColorScheme.light, .dark] {
            let host = NSHostingView(rootView: DecisionChoices(item: item) { _ in }
                .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .environment(\.colorScheme, scheme))
            let window = makeWindow(host, width: 300, scheme: scheme)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(350))
            let bitmap = try capture(host)
            let text = try recognize(bitmap)
            let first = try XCTUnwrap(text.first { $0.text.contains("Deploy") })
            let second = try XCTUnwrap(text.first { $0.text.contains("Not yet") })
            let wrapped = try XCTUnwrap(text.first { $0.text.contains("Investigate") })
            XCTAssertEqual(first.bounds.midY, second.bounds.midY, accuracy: 0.01)
            XCTAssertLessThan(wrapped.bounds.midY, first.bounds.midY)
            try assertInkFill(bitmap, textY: first.bounds.midY, scheme: scheme)
        }
    }

    func testZeroCountChipsAreAbsentAndLiveRemainsVisible() async throws {
        let now = Date.now
        let decision = AttentionTestSupport.ask(id: "open", options: ["Ship"],
            sessionStatus: "waiting", now: now)
        let working = AttentionTestSupport.ask(id: "working", options: [], sessionStatus: "working", now: now)
        for history in [[], [decision], [working], [decision, working]] {
            let snapshot = OverviewSnapshot(history: history, live: nil, now: now,
                health: .live(checkedAt: now), coverageComplete: true, requiredInputs: history).today
            let host = NSHostingView(rootView: TodaySummary(snapshot: snapshot, now: now))
            let window = makeWindow(host, width: 400, scheme: .light)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(350))
            let labels = try recognize(capture(host)).map(\.text)
            XCTAssertEqual(labels.contains { $0.contains("need you") },
                !snapshot.decisions.isEmpty, "\(labels)")
            XCTAssertEqual(labels.contains { $0.contains("working") }, !snapshot.working.isEmpty, "\(labels)")
            XCTAssertTrue(labels.contains { $0.contains("Live") })
        }
    }

    func testResolvedDecisionNeverRendersTheDefaultLineInBothAppearances() async throws {
        let now = Date.now
        for status in ["replied", "expired"] {
            let message = AttentionTestSupport.ask(id: "resolved", options: ["Ship", "Hold"],
                defaultOption: "Hold", status: status, now: now)
            for scheme in [ColorScheme.light, .dark] {
                let host = NSHostingView(rootView: HistoryThreadRow(thread: MessageThread(message: message),
                    usesV4: true, reply: AttentionReplyState(), isExpanded: .constant(true),
                    isSearching: false, onCollapse: {}, onChoose: { _ in nil })
                    .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(TodayStyle.ground)
                    .environment(\.colorScheme, scheme))
                host.sizingOptions = []
                let window = makeWindow(host, width: 600, scheme: scheme)
                window.setContentSize(NSSize(width: 600, height: 500))
                defer { window.close() }
                try await Task.sleep(for: .milliseconds(350))
                let labels = try recognize(capture(host)).map(\.text)
                XCTAssertFalse(labels.contains { $0.contains("Default:") || $0.contains("No answer in") },
                    "\(labels)")
                XCTAssertTrue(labels.contains { $0.contains("Resolved") || $0.contains("Expired") },
                    "\(labels)")
            }
        }
    }

    func testUntimedDecisionShowsNoDeadlineExactlyOnceInBothAppearances() async throws {
        let now = Date.now
        let message = AttentionTestSupport.ask(id: "untimed", options: ["Ship", "Hold"],
            defaultOption: "Hold", now: now)
        let item = AttentionItem(message: message, group: .priority)
        for scheme in [ColorScheme.light, .dark] {
            let host = NSHostingView(rootView: TodayDecisionCard(item: item, now: now, isSelected: false,
                isSubmitting: false, error: nil, onSelect: {}, onChoose: { _ in })
                .environment(\.colorScheme, scheme))
            let window = makeWindow(host, width: 600, scheme: scheme)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(350))
            let labels = try recognize(capture(host)).map(\.text)
            XCTAssertEqual(labels.filter { $0.localizedCaseInsensitiveContains("No deadline") }.count, 1,
                "\(labels)")
            XCTAssertTrue(labels.contains { $0.contains("Default:") && $0.contains("not approval") },
                "\(labels)")
        }
    }

    private func capture(_ host: NSView) throws -> NSBitmapImageRep {
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    private func recognize(_ bitmap: NSBitmapImageRep) throws -> [(text: String, bounds: CGRect)] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        return (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { ($0.string, observation.boundingBox) }
        }
    }

    private func makeWindow(_ host: NSView, width: CGFloat, scheme: ColorScheme) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: width, height: 220),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        host.appearance = window.appearance
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func assertInkFill(_ bitmap: NSBitmapImageRep, textY: CGFloat, scheme: ColorScheme) throws {
        let scale = CGFloat(bitmap.pixelsWide) / 300
        let pixel = try XCTUnwrap(bitmap.colorAt(x: Int(17 * scale),
            y: Int((1 - textY) * CGFloat(bitmap.pixelsHigh)))?.usingColorSpace(.deviceRGB))
        let ink = try XCTUnwrap(NSColor(named: "Ink", bundle: appResourceBundle))
        let appearance = try XCTUnwrap(NSAppearance(named: scheme == .light ? .aqua : .darkAqua))
        appearance.performAsCurrentDrawingAppearance {
            let expected = ink.usingColorSpace(.deviceRGB) ?? .clear
            XCTAssertEqual(pixel.redComponent, expected.redComponent, accuracy: 0.04)
            XCTAssertEqual(pixel.greenComponent, expected.greenComponent, accuracy: 0.04)
            XCTAssertEqual(pixel.blueComponent, expected.blueComponent, accuracy: 0.04)
        }
    }
}
