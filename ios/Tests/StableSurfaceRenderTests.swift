// Rendered geometry regressions for cached Home, lists, panels and fallback retries.
// Exports StableSurfaceRenderTests; hosts the real SwiftUI surfaces on the test simulator.
// Dependencies: XCTest, UIKit, SwiftUI, and the iOS app target.

import HibossKit
import SwiftUI
import UIKit
import XCTest
@testable import HiBoss

@MainActor
final class StableSurfaceRenderTests: XCTestCase {
    func testWorkingChipRendersTheGreenSemanticColor() throws {
        let now = Date()
        let message = HistoryMessage(id: "work", body: "Working", direction: "agent_to_boss",
                                     status: "delivered", priority: "normal", mode: "async",
                                     createdAt: now.ISO8601Format(), sessionId: "work",
                                     sessionStatus: "working")
        let snapshot = TodaySnapshot(history: [message], health: .loading,
                                     coverageComplete: false, now: now)
        let header = TodayHeader(snapshot: snapshot, requestCount: 0, now: now, onSettings: {})
        let renderer = ImageRenderer(content: header.environment(\.colorScheme, .light))
        renderer.proposedSize = ProposedViewSize(width: 390, height: nil)
        let image = try XCTUnwrap(renderer.cgImage)
        let pixels = try rgbaPixels(image)
        let green = stride(from: 0, to: pixels.count, by: 4).filter {
            Int(pixels[$0 + 1]) > Int(pixels[$0]) + 30 && Int(pixels[$0 + 1]) > Int(pixels[$0 + 2]) + 30
        }.count
        XCTAssertGreaterThan(green, 5, "The working chip must render green, including its dot")
    }

    func testHomeCachedStatusDoesNotMoveAllClear() async {
        let snapshot = HomeAttentionSnapshot(messages: [], withdrawn: [], questionnaires: [], now: .now)
        let settled = section(snapshot, status: nil)
        let refreshing = section(snapshot, status: "Reconnecting", failure: false)
        let failed = section(snapshot, status: "Offline", failure: true)
        let baseline = await height(settled)
        let held = await height(refreshing)
        let error = await height(failed)
        XCTAssertEqual(held, baseline, accuracy: 1)
        XCTAssertEqual(error, baseline, accuracy: 1)
    }

    func testPanelNoticeKeepsItsReservedHeightThroughRecovery() async {
        let settled = await height(PanelPendingNotice(freshness: .live, retry: {}))
        let pending = await height(PanelPendingNotice(freshness: .awaitingData, retry: {}))
        XCTAssertEqual(pending, settled, accuracy: 1)
    }

    func testListRefreshDoesNotShrinkTheContentViewport() async {
        let settled = await viewport(loading: false, error: nil)
        let refreshing = await viewport(loading: true, error: nil)
        let failed = await viewport(loading: false, error: "Offline")
        XCTAssertEqual(refreshing, settled)
        XCTAssertEqual(failed, settled)
    }

    func testHomeHealthChipKeepsItsWidth() async {
        let health = TodaySnapshot(history: [], requiredInputs: [], health: .live(checkedAt: .now),
                                   coverageComplete: true, now: .now)
        let settled = await height(TodayHeader(snapshot: health, requestCount: 1, now: .now,
                                               onSettings: {}), width: 220)
        let pending = await height(TodayHeader(snapshot: health, requestCount: 1, isRefreshing: true,
                                               now: .now, onSettings: {}), width: 220)
        XCTAssertEqual(pending, settled, accuracy: 1)
    }

    func testRefreshDoesNotImmediatelyChangeTheHomeStatusLabel() throws {
        let now = Date()
        let snapshot = TodaySnapshot(history: [], requiredInputs: [], health: .live(checkedAt: now),
                                     coverageComplete: true, now: now)
        let settled = ImageRenderer(content: TodayHeader(snapshot: snapshot, requestCount: 0,
                                                        now: now, onSettings: {}))
        let refreshing = ImageRenderer(content: TodayHeader(snapshot: snapshot, requestCount: 0,
                                                           isRefreshing: true, now: now, onSettings: {}))
        settled.proposedSize = ProposedViewSize(width: 390, height: nil)
        refreshing.proposedSize = settled.proposedSize
        XCTAssertEqual(try XCTUnwrap(settled.uiImage?.pngData()),
                       try XCTUnwrap(refreshing.uiImage?.pngData()))
    }

    func testOpenDetailSurvivesEvictionFromTheBoundedHistory() async throws {
        let store = InboxStore(decisionAlertsEnabled: false)
        let message = HistoryMessage(id: "old", body: "Loaded detail", direction: "agent_to_boss",
                                     status: "delivered", priority: "normal", createdAt: "")
        store.history = [message]
        let window = window(width: 390)
        window.rootViewController = UIHostingController(rootView: NavigationStack {
            MessageDetailView(store: store, messageID: message.id)
        })
        window.isHidden = false
        defer { window.isHidden = true }
        await settle()
        let before = image(window)
        attach(before, name: "detail-before-eviction")
        store.history = []
        await settle()
        let after = image(window)
        attach(after, name: "detail-after-eviction")
        XCTAssertEqual(before.pngData(), after.pngData(),
                       "Eviction must not return an open detail to loading")
    }

    private func image(_ window: UIWindow) -> UIImage {
        window.layoutIfNeeded()
        return UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = "en-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testRequiredInputReplacementHasNoRenderedMissingFrame() async {
        let api = ControlledInputAPI()
        let original = HistoryMessage(id: "decision", body: "Original", direction: "agent_to_boss",
                                      status: "delivered", priority: "normal", createdAt: "")
        let replacement = HistoryMessage(id: original.id, body: "Replacement", direction: "agent_to_boss",
                                         status: "delivered", priority: "normal", createdAt: "")
        await api.setResponse([original])
        let store = InboxStore(decisionAlertsEnabled: false)
        store.api = api
        store.requiredInputs = [original]
        store.requiredInputLoaded = true
        store.startRequiredInputs(api)
        defer { store.stop() }
        await api.waitForStream(0)
        let probe = ReplacementFrames()
        let window = window(width: 390)
        window.rootViewController = UIHostingController(rootView:
            RequiredInputFrameProbe(store: store, frames: probe))
        window.isHidden = false
        defer { window.isHidden = true }
        await settle()
        await api.send(.message(replacement), to: 0)
        await settle()
        XCTAssertEqual(probe.lastBody, "Replacement", "The replacement must reach a rendered frame")
        XCTAssertEqual(probe.missing, 0, "Two same-turn mutations were coalesced in this rendered case")
    }

    private func section(_ snapshot: HomeAttentionSnapshot, status: String?, failure: Bool = false)
        -> some View {
        HomeAttentionSection(snapshot: snapshot, hasPanels: false, isAllClear: true, status: status,
                             statusIsFailure: failure, onChoose: { _, _ in }, onOpenPanel: { _ in },
                             onOpenSession: { _ in }, onOpenDecision: { _ in })
    }

    private func height<V: View>(_ view: V, width: CGFloat = 390) async -> CGFloat {
        let host = UIHostingController(rootView: view)
        let window = window(width: width)
        window.rootViewController = host
        window.isHidden = false
        await settle()
        let height = host.sizeThatFits(in: CGSize(width: width, height: 10_000)).height
        window.isHidden = true
        return height
    }

    private func viewport(loading: Bool, error: String?) async -> CGRect {
        let recorder = FrameRecorder()
        let view = ListStateView(isLoading: loading, error: error, isEmpty: false,
                                 emptyIcon: "tray", emptyTitle: "Empty", emptyDetail: "No items",
                                 hasLoaded: true, onRetry: {}) {
            Color.clear.overlay {
                GeometryReader { geometry in
                    Color.clear.preference(key: SurfaceFrameKey.self, value: geometry.frame(in: .global))
                }
            }.onPreferenceChange(SurfaceFrameKey.self) { recorder.frame = $0 }
        }
        let host = UIHostingController(rootView: view)
        let window = window(width: 390)
        window.rootViewController = host
        window.isHidden = false
        await settle()
        window.isHidden = true
        return recorder.frame
    }

    private func window(width: CGFloat) -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 844)
        return window
    }

    private func settle() async {
        let done = expectation(description: "render delayed refresh feedback")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { done.fulfill() }
        await fulfillment(of: [done], timeout: 2)
    }
}

private final class FrameRecorder: @unchecked Sendable {
    var frame: CGRect = .zero
}

private struct SurfaceFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private final class ReplacementFrames: @unchecked Sendable {
    var missing = 0
    var lastBody: String?
}

private struct RequiredInputFrameProbe: View {
    @ObservedObject var store: InboxStore
    let frames: ReplacementFrames

    var body: some View {
        Group {
            if let message = store.requiredInputs.first {
                Text(verbatim: message.body)
                    .onChange(of: message.body, initial: true) { _, body in frames.lastBody = body }
            } else {
                Text("Absent").onAppear { frames.missing += 1 }
            }
        }
    }
}
